import CoreMedia
import Defaults
import Foundation
import Libmpv
import Logging
#if !os(macOS)
    import Siesta
    import UIKit
#else
    import AppKit
#endif

final class MPVClient: ObservableObject {
    static var logFile: URL {
        YatteeApp.logsDirectory.appendingPathComponent("yattee-\(YatteeApp.build)-mpv-log.txt")
    }

    private var logger = Logger(label: "mpv-client")
    private var needsDrawingCooldown = false
    private var needsDrawingWorkItem: DispatchWorkItem?

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
    var currentRefreshRate = 60

    func create(frame: CGRect? = nil) {
        #if !os(macOS)
            if let frame {
                glView = MPVOGLView(frame: frame)
            }
        #endif

        mpv = mpv_create()
        if mpv == nil {
            logger.critical("failed creating context\n")
            exit(1)
        }

        if Defaults[.mpvEnableLogging] {
            checkError(mpv_set_option_string(
                mpv,
                "log-file",
                Self.logFile.absoluteString.replacingOccurrences(of: "file://", with: "")
            ))
            checkError(mpv_request_log_messages(mpv, "debug"))
        } else {
            #if DEBUG
                checkError(mpv_request_log_messages(mpv, "debug"))
            #else
                checkError(mpv_request_log_messages(mpv, "no"))
            #endif
        }

        #if os(macOS)
            checkError(mpv_set_option_string(mpv, "input-media-keys", "yes"))
        #endif

        // CACHING //

        checkError(mpv_set_option_string(mpv, "cache-pause-initial", Defaults[.mpvCachePauseInital] ? "yes" : "no"))
        checkError(mpv_set_option_string(mpv, "cache-secs", Defaults[.mpvCacheSecs]))
        checkError(mpv_set_option_string(mpv, "cache-pause-wait", Defaults[.mpvCachePauseWait]))

        // PLAYBACK //
        checkError(mpv_set_option_string(mpv, "keep-open", "yes"))
        checkError(mpv_set_option_string(mpv, "deinterlace", Defaults[.mpvDeinterlace] ? "yes" : "no"))
        checkError(mpv_set_option_string(mpv, "sub-scale", Defaults[.captionsFontScaleSize]))
        checkError(mpv_set_option_string(mpv, "sub-color", Defaults[.captionsFontColor]))
        checkError(mpv_set_option_string(mpv, "user-agent", UserAgentManager.shared.userAgent))
        checkError(mpv_set_option_string(mpv, "initial-audio-sync", Defaults[.mpvInitialAudioSync] ? "yes" : "no"))

        // Enable VSYNC – needed for `video-sync`
        if Defaults[.mpvSetRefreshToContentFPS] {
            checkError(mpv_set_option_string(mpv, "opengl-swapinterval", "1"))
            checkError(mpv_set_option_string(mpv, "video-sync", "display-resample"))
            checkError(mpv_set_option_string(mpv, "interpolation", "yes"))
            checkError(mpv_set_option_string(mpv, "tscale", "mitchell"))
            checkError(mpv_set_option_string(mpv, "tscale-window", "blackman"))
            checkError(mpv_set_option_string(mpv, "vd-lavc-framedrop", "nonref"))
            checkError(mpv_set_option_string(mpv, "display-fps-override", "\(String(getScreenRefreshRate()))"))
        }

        // CPU //

        // Determine number of threads based on system core count
        let numberOfCores = ProcessInfo.processInfo.processorCount
        let threads = numberOfCores * 2

        // Log the number of cores and threads
        logger.info("Number of CPU cores: \(numberOfCores)")

        // Set the number of threads dynamically
        checkError(mpv_set_option_string(mpv, "vd-lavc-threads", "\(threads)"))

        // GPU //

        checkError(mpv_set_option_string(mpv, "hwdec", Defaults[.mpvHWdec]))
        checkError(mpv_set_option_string(mpv, "vo", "libmpv"))

        // We set set everything to OpenGL so MPV doesn't have to probe for other APIs.
        checkError(mpv_set_option_string(mpv, "gpu-api", "opengl"))

        #if !os(macOS)
            checkError(mpv_set_option_string(mpv, "opengl-es", "yes"))
        #endif

        // We set this to ordered since we use OpenGL and Apple's implementation is ancient.
        checkError(mpv_set_option_string(mpv, "dither", "ordered"))

        // DEMUXER //

        // We request to test for lavf first and skip probing other demuxer.
        checkError(mpv_set_option_string(mpv, "demuxer", "lavf"))
        checkError(mpv_set_option_string(mpv, "audio-demuxer", "lavf"))
        checkError(mpv_set_option_string(mpv, "sub-demuxer", "lavf"))
        checkError(mpv_set_option_string(mpv, "demuxer-lavf-analyzeduration", "1"))
        checkError(mpv_set_option_string(mpv, "demuxer-lavf-probe-info", Defaults[.mpvDemuxerLavfProbeInfo]))

        // Disable ytdl, since it causes crashes on macOS.
        #if os(macOS)
            checkError(mpv_set_option_string(mpv, "ytdl", "no"))
        #endif

        checkError(mpv_initialize(mpv))

        let api = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String)
        var initParams = mpv_opengl_init_params(
            get_proc_address: getProcAddress,
            get_proc_address_ctx: nil
        )

        queue = DispatchQueue(label: "mpv", qos: .userInteractive, attributes: [.concurrent])

        withUnsafeMutablePointer(to: &initParams) { initParams in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: initParams),
                mpv_render_param()
            ]

            if mpv_render_context_create(&mpvGL, mpv, &params) < 0 {
                logger.critical("failed to initialize mpv GL context")
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

        mpv_set_wakeup_callback(mpv, wakeUp, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "core-idle", MPV_FORMAT_FLAG)
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

    func loadFile(
        _ url: URL,
        audio: URL? = nil,
        bitrate: Int? = nil,
        kind: Stream.Kind,
        sub: URL? = nil,
        time: CMTime? = nil,
        forceSeekable: Bool = false,
        completionHandler: ((Int32) -> Void)? = nil
    ) {
        var args = [url.absoluteString]
        var options = [String]()

        args.append("replace")

        // needed since mpvkit 0.38.0
        // https://github.com/mpv-player/mpv/issues/13806#issuecomment-2029818905
        args.append("-1")

        if let time, time.seconds > 0 {
            options.append("start=\(Int(time.seconds))")
        }

        if let audioURL = audio?.absoluteString {
            options.append("audio-files-append=\"\(audioURL)\"")
        }

        if let subURL = sub?.absoluteString {
            options.append("sub-files-append=\"\(subURL)\"")
        }

        if forceSeekable {
            options.append("force-seekable=yes")
            // this is needed for peertube?
            // options.append("stream-lavf-o=seekable=0")
        }

        if !options.isEmpty {
            args.append(options.joined(separator: ","))
        }

        if kind == .hls, bitrate != 0 {
            checkError(mpv_set_option_string(mpv, "hls-bitrate", String(describing: bitrate)))
        }

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

    var videoFormat: String {
        stringOrUnknown("video-format")
    }

    var videoCodec: String {
        stringOrUnknown("video-codec")
    }

    var currentVo: String {
        stringOrUnknown("current-vo")
    }

    var width: String {
        stringOrUnknown("width")
    }

    var height: String {
        stringOrUnknown("height")
    }

    var videoBitrate: Double {
        mpv.isNil ? 0.0 : getDouble("video-bitrate")
    }

    var audioFormat: String {
        stringOrUnknown("audio-params/format")
    }

    var audioCodec: String {
        stringOrUnknown("audio-codec")
    }

    var currentAo: String {
        stringOrUnknown("current-ao")
    }

    var audioChannels: String {
        stringOrUnknown("audio-params/channels")
    }

    var audioSampleRate: String {
        stringOrUnknown("audio-params/samplerate")
    }

    var aspectRatio: Double {
        guard !mpv.isNil else { return VideoPlayerView.defaultAspectRatio }
        let aspect = getDouble("video-params/aspect")
        return aspect.isZero ? VideoPlayerView.defaultAspectRatio : aspect
    }

    var dh: Double {
        let defaultDh = 500.0
        guard !mpv.isNil else { return defaultDh }

        let dh = getDouble("video-params/dh")
        return dh.isZero ? defaultDh : dh
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

    var currentContainerFps: Int {
        guard !mpv.isNil else { return 30 }
        let fps = getDouble("container-fps")
        return Int(fps.rounded())
    }

    func areSubtitlesAdded() async -> Bool {
        guard !mpv.isNil else { return false }

        let trackCount = await Task(operation: { getInt("track-list/count") }).value
        guard trackCount > 0 else { return false }

        for index in 0 ..< trackCount {
            if let trackType = await Task(operation: { getString("track-list/\(index)/type") }).value, trackType == "sub" {
                return true
            }
        }
        return false
    }

    func logCurrentFps() {
        let fps = currentContainerFps
        logger.info("Current container FPS: \(fps)")
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

            DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
                guard let self else { return }
                let model = self.backend.model
                let aspectRatio = self.aspectRatio > 0 && self.aspectRatio < VideoPlayerView.defaultAspectRatio ? self.aspectRatio : VideoPlayerView.defaultAspectRatio
                let height = [model.playerSize.height, model.playerSize.width / aspectRatio].min()!
                var insets = 0.0
                #if os(iOS)
                    insets = OrientationTracker.shared.currentInterfaceOrientation.isPortrait ? SafeAreaModel.shared.safeArea.bottom : 0
                #endif
                let offsetY = max(0, model.playingFullScreen ? ((model.playerSize.height / 2.0) - ((height + insets) / 2)) : 0)
                UIView.animate(withDuration: 0.2, animations: {
                    self.glView?.frame = CGRect(x: 0, y: offsetY, width: roundedWidth, height: height)
                }) { completion in
                    if completion {
                        self.logger.info("setting player size to \(roundedWidth),\(roundedHeight) FINISHED")

                        self.glView?.queue.async {
                            self.glView.display()
                        }
                        self.backend?.controls.objectWillChange.send()
                    }
                }
            }

        #endif
    }

    func setNeedsDrawing(_ needsDrawing: Bool) {
        // Check if we are currently in a cooldown period
        guard !needsDrawingCooldown else {
            logger.info("Not drawing, cooldown in progress")
            return
        }

        logger.info("needs drawing: \(needsDrawing)")

        // Set the cooldown flag to true and cancel any existing work item
        needsDrawingCooldown = true
        needsDrawingWorkItem?.cancel()

        #if !os(macOS)
            glView?.needsDrawing = needsDrawing
        #endif

        // Create a new DispatchWorkItem to reset the cooldown flag after 0.1 seconds
        let workItem = DispatchWorkItem { [weak self] in
            self?.needsDrawingCooldown = false
        }
        needsDrawingWorkItem = workItem

        // Schedule the cooldown reset after 0.1 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
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

    func updateRefreshRate(to refreshRate: Int) {
        setString("display-fps-override", "\(String(refreshRate))")
        logger.info("Updated refresh rate during playback to: \(refreshRate) Hz")
    }

    // Retrieve the screen's current refresh rate dynamically.
    func getScreenRefreshRate() -> Int {
        var refreshRate = 60 // Default to 60 Hz in case of failure

        #if os(macOS)
            // macOS implementation using NSScreen
            if let screen = NSScreen.main,
               let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               let mode = CGDisplayCopyDisplayMode(displayID),
               mode.refreshRate > 0
            {
                refreshRate = Int(mode.refreshRate)
                logger.info("Screen refresh rate: \(refreshRate) Hz")
            } else {
                logger.warning("Failed to get refresh rate from NSScreen.")
            }
        #else
            // iOS implementation using UIScreen with a failover
            let mainScreen = UIScreen.main
            refreshRate = mainScreen.maximumFramesPerSecond

            // Failover: if maximumFramesPerSecond is 0 or an unexpected value
            if refreshRate <= 0 {
                refreshRate = 60 // Fallback to 60 Hz
                logger.warning("Failed to get refresh rate from UIScreen, falling back to 60 Hz.")
            } else {
                logger.info("Screen refresh rate: \(refreshRate) Hz")
            }
        #endif

        currentRefreshRate = refreshRate
        return refreshRate
    }

    func addVideoTrack(_ url: URL) {
        command("video-add", args: [url.absoluteString])
    }

    func addSubTrack(_ url: URL) async {
        await Task {
            command("sub-add", args: [url.absoluteString])
        }.value
    }

    func removeSubs() async {
        await Task {
            command("sub-remove")
        }.value
    }

    func setVideoToAuto() {
        setString("video", "1")
    }

    func setVideoToNo() {
        setString("video", "no")
    }

    func setSubToAuto() {
        setString("sub", "auto")
    }

    func setSubToNo() {
        setString("sub", "no")
    }

    func setSubFontSize(scaleSize: String) {
        setString("sub-scale", scaleSize)
    }

    func setSubFontColor(color: String) {
        setString("sub-color", color)
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
        guard mpv != nil else { return }
        var data: Int = flag ? 1 : 0
        mpv_set_property_async(mpv, 0, name, MPV_FORMAT_FLAG, &data)
    }

    func setDoubleAsync(_ name: String, _ value: Double) {
        guard mpv != nil else { return }
        var data = value
        mpv_set_property_async(mpv, 0, name, MPV_FORMAT_DOUBLE, &data)
    }

    private func getDouble(_ name: String) -> Double {
        guard mpv != nil else { return 0.0 }
        var data = Double()
        mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
        return data
    }

    private func getInt(_ name: String) -> Int {
        guard mpv != nil else { return 0 }
        var data = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_INT64, &data)
        return Int(data)
    }

    func getString(_ name: String) -> String? {
        guard mpv != nil else { return nil }
        let cstr = mpv_get_property_string(mpv, name)
        let str: String? = cstr == nil ? nil : String(cString: cstr!)
        mpv_free(cstr)
        return str
    }

    private func setString(_ name: String, _ value: String) {
        guard mpv != nil else { return }
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

    private func stringOrUnknown(_ name: String) -> String {
        mpv.isNil ? "unknown" : (getString(name) ?? "unknown")
    }

    private var machine: String {
        var systeminfo = utsname()
        uname(&systeminfo)
        return withUnsafeBytes(of: &systeminfo.machine) { bufPtr -> String in
            let data = Data(bufPtr)
            if let lastIndex = data.lastIndex(where: { $0 != 0 }) {
                return String(data: data[0 ... lastIndex], encoding: .isoLatin1)!
            }
            return String(data: data, encoding: .isoLatin1)!
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
