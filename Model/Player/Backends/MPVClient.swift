import CoreMedia
import Defaults
import Foundation
import Logging
#if !os(macOS)
    import Siesta
    import UIKit
#endif

final class MPVClient: ObservableObject {
    private var logger = Logger(label: "mpv-client")

    var mpv: OpaquePointer!
    var mpvGL: OpaquePointer!
    var queue: DispatchQueue!
    #if os(macOS)
        var layer: VideoLayer!
        var link: CVDisplayLink!
    #else
        var glView: MPVOGLView!
    #endif
    var backend: MPVBackend!

    var seeking = false

    func create(frame: CGRect? = nil) {
        #if !os(macOS)
            if let frame = frame {
                glView = MPVOGLView(frame: frame)
            }
        #endif

        mpv = mpv_create()
        if mpv == nil {
            print("failed creating context\n")
            exit(1)
        }

        #if DEBUG
            checkError(mpv_request_log_messages(mpv, "debug"))
        #else
            checkError(mpv_request_log_messages(mpv, "warn"))
        #endif

        #if os(macOS)
            checkError(mpv_set_option_string(mpv, "input-media-keys", "yes"))
        #endif

        checkError(mpv_set_option_string(mpv, "cache-pause-initial", "yes"))
        checkError(mpv_set_option_string(mpv, "cache-secs", Defaults[.mpvCacheSecs]))
        checkError(mpv_set_option_string(mpv, "cache-pause-wait", Defaults[.mpvCachePauseWait]))
        checkError(mpv_set_option_string(mpv, "keep-open", "yes"))
        checkError(mpv_set_option_string(mpv, "hwdec", machine == "x86_64" ? "no" : "auto-safe"))
        checkError(mpv_set_option_string(mpv, "vo", "libmpv"))

        checkError(mpv_initialize(mpv))

        let api = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String)
        var initParams = mpv_opengl_init_params(
            get_proc_address: getProcAddress,
            get_proc_address_ctx: nil,
            extra_exts: nil
        )

        queue = DispatchQueue(label: "mpv", qos: .userInteractive)

        withUnsafeMutablePointer(to: &initParams) { initParams in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: initParams),
                mpv_render_param()
            ]

            if mpv_render_context_create(&mpvGL, mpv, &params) < 0 {
                puts("failed to initialize mpv GL context")
                exit(1)
            }

            #if os(macOS)
                mpv_render_context_set_update_callback(
                    mpvGL,
                    glUpdate,
                    UnsafeMutableRawPointer(Unmanaged.passUnretained(layer).toOpaque())
                )
            #else
                glView.mpvGL = UnsafeMutableRawPointer(mpvGL)

                mpv_render_context_set_update_callback(
                    mpvGL,
                    glUpdate(_:),
                    UnsafeMutableRawPointer(Unmanaged.passUnretained(glView).toOpaque())
                )
            #endif
        }

        queue!.async {
            mpv_set_wakeup_callback(self.mpv, wakeUp, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        }
    }

    func readEvents() {
        queue?.async { [self] in
            while self.mpv != nil {
                let event = mpv_wait_event(self.mpv, 0)
                if event!.pointee.event_id == MPV_EVENT_NONE {
                    break
                }
                backend?.handle(event)
            }
        }
    }

    func loadFile(_ url: URL, audio: URL? = nil, sub: URL? = nil, time: CMTime? = nil, completionHandler: ((Int32) -> Void)? = nil) {
        var args = [url.absoluteString]
        var options = [String]()

        if let time = time {
            args.append("replace")
            options.append("start=\(Int(time.seconds))")
        }

        if let audioURL = audio?.absoluteString {
            options.append("audio-files-append=\"\(audioURL)\"")
        }

        if let subURL = sub?.absoluteString {
            options.append("sub-files-append=\"\(subURL)\"")
        }

        args.append(options.joined(separator: ","))

        command("loadfile", args: args, returnValueCallback: completionHandler)
    }

    func play() {
        setFlagAsync("pause", false)
    }

    func pause() {
        setFlagAsync("pause", true)
    }

    func togglePlay() {
        command("cycle", args: ["pause"])
    }

    func stop() {
        command("stop")
    }

    var currentTime: CMTime {
        CMTime.secondsInDefaultTimescale(mpv.isNil ? -1 : getDouble("time-pos"))
    }

    var frameDropCount: Int {
        mpv.isNil ? 0 : getInt("frame-drop-count")
    }

    var outputFps: Double {
        mpv.isNil ? 0.0 : getDouble("estimated-vf-fps")
    }

    var hwDecoder: String {
        mpv.isNil ? "unknown" : (getString("hwdec-current") ?? "unknown")
    }

    var bufferingState: Double {
        mpv.isNil ? 0.0 : getDouble("cache-buffering-state")
    }

    var cacheDuration: Double {
        mpv.isNil ? 0.0 : getDouble("demuxer-cache-duration")
    }

    var duration: CMTime {
        CMTime.secondsInDefaultTimescale(mpv.isNil ? -1 : getDouble("duration"))
    }

    var pausedForCache: Bool {
        mpv.isNil ? false : getFlag("paused-for-cache")
    }

    var eofReached: Bool {
        mpv.isNil ? false : getFlag("eof-reached")
    }

    func seek(relative time: CMTime, completionHandler: ((Bool) -> Void)? = nil) {
        guard !seeking else {
            logger.warning("ignoring seek, another in progress")
            return
        }

        seeking = true
        command("seek", args: [String(time.seconds)]) { [weak self] _ in
            self?.seeking = false
            completionHandler?(true)
        }
    }

    func seek(to time: CMTime, completionHandler: ((Bool) -> Void)? = nil) {
        guard !seeking else {
            logger.warning("ignoring seek, another in progress")
            return
        }

        seeking = true
        command("seek", args: [String(time.seconds), "absolute"]) { [weak self] _ in
            self?.seeking = false
            completionHandler?(true)
        }
    }

    func setSize(_ width: Double, _ height: Double) {
        let roundedWidth = width.rounded()
        let roundedHeight = height.rounded()

        guard width > 0, height > 0 else {
            return
        }

        logger.info("setting player size to \(roundedWidth),\(roundedHeight)")
        #if !os(macOS)
            guard roundedWidth <= UIScreen.main.bounds.width, roundedHeight <= UIScreen.main.bounds.height else {
                logger.info("requested size is greater than screen size, ignoring")
                logger.info("width: \(roundedWidth) <= \(UIScreen.main.bounds.width)")
                logger.info("height: \(roundedHeight) <= \(UIScreen.main.bounds.height)")
                return
            }

            glView?.frame = CGRect(x: 0, y: 0, width: roundedWidth, height: roundedHeight)
        #endif
    }

    func setNeedsDrawing(_ needsDrawing: Bool) {
        logger.info("needs drawing: \(needsDrawing)")
        #if !os(macOS)
            glView.needsDrawing = needsDrawing
        #endif
    }

    func command(
        _ command: String,
        args: [String?] = [],
        checkForErrors: Bool = true,
        returnValueCallback: ((Int32) -> Void)? = nil
    ) {
        guard mpv != nil else {
            return
        }
        var cargs = makeCArgs(command, args).map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
        defer {
            for ptr in cargs where ptr != nil {
                free(UnsafeMutablePointer(mutating: ptr!))
            }
        }
        logger.info("\(command) -- \(args)")
        let returnValue = mpv_command(mpv, &cargs)
        if checkForErrors {
            checkError(returnValue)
        }
        if let cb = returnValueCallback {
            cb(returnValue)
        }
    }

    func addVideoTrack(_ url: URL) {
        command("video-add", args: [url.absoluteString])
    }

    func addSubTrack(_ url: URL) {
        command("sub-add", args: [url.absoluteString])
    }

    func removeSubs() {
        command("sub-remove")
    }

    func setVideoToAuto() {
        setString("video", "1")
    }

    func setVideoToNo() {
        setString("video", "no")
    }

    var tracksCount: Int {
        Int(getString("track-list/count") ?? "-1") ?? -1
    }

    private func getFlag(_ name: String) -> Bool {
        var data = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &data)
        return data > 0
    }

    private func setFlagAsync(_ name: String, _ flag: Bool) {
        var data: Int = flag ? 1 : 0
        mpv_set_property_async(mpv, 0, name, MPV_FORMAT_FLAG, &data)
    }

    func setDoubleAsync(_ name: String, _ value: Double) {
        var data = value
        mpv_set_property_async(mpv, 0, name, MPV_FORMAT_DOUBLE, &data)
    }

    private func getDouble(_ name: String) -> Double {
        var data = Double()
        mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
        return data
    }

    private func getInt(_ name: String) -> Int {
        var data = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_INT64, &data)
        return Int(data)
    }

    func getString(_ name: String) -> String? {
        let cstr = mpv_get_property_string(mpv, name)
        let str: String? = cstr == nil ? nil : String(cString: cstr!)
        mpv_free(cstr)
        return str
    }

    private func setString(_ name: String, _ value: String) {
        mpv_set_property_string(mpv, name, value)
    }

    private func makeCArgs(_ command: String, _ args: [String?]) -> [String?] {
        if !args.isEmpty, args.last == nil {
            fatalError("Command do not need a nil suffix")
        }

        var strArgs = args
        strArgs.insert(command, at: 0)
        strArgs.append(nil)

        return strArgs
    }

    private func checkError(_ status: CInt) {
        if status < 0 {
            logger.error(.init(stringLiteral: "MPV API error: \(String(cString: mpv_error_string(status)))\n"))
        }
    }

    private var machine: String {
        var systeminfo = utsname()
        uname(&systeminfo)
        return withUnsafeBytes(of: &systeminfo.machine) { bufPtr -> String in
            let data = Data(bufPtr)
            if let lastIndex = data.lastIndex(where: { $0 != 0 }) {
                return String(data: data[0 ... lastIndex], encoding: .isoLatin1)!
            } else {
                return String(data: data, encoding: .isoLatin1)!
            }
        }
    }
}

#if os(macOS)
    func getProcAddress(_: UnsafeMutableRawPointer?, _ name: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer? {
        let symbolName = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
        let identifier = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString)

        return CFBundleGetFunctionPointerForName(identifier, symbolName)
    }

    func glUpdate(_ ctx: UnsafeMutableRawPointer?) {
        let videoLayer = unsafeBitCast(ctx, to: VideoLayer.self)

        videoLayer.client?.queue?.async {
            if !videoLayer.isAsynchronous {
                videoLayer.display()
            }
        }
    }
#else
    func getProcAddress(_: UnsafeMutableRawPointer?, _ name: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer? {
        let symbolName = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
        let identifier = CFBundleGetBundleWithIdentifier("com.apple.opengles" as CFString)

        return CFBundleGetFunctionPointerForName(identifier, symbolName)
    }

    private func glUpdate(_ ctx: UnsafeMutableRawPointer?) {
        #if targetEnvironment(simulator)
            // performance of drawing in simulator is poor and buggy, disable it
            return
        #endif

        let glView = unsafeBitCast(ctx, to: MPVOGLView.self)

        guard glView.needsDrawing else {
            return
        }

        glView.queue.async {
            glView.display()
        }
    }

#endif
private func wakeUp(_ context: UnsafeMutableRawPointer?) {
    let client = unsafeBitCast(context, to: MPVClient.self)
    client.readEvents()
}
