//
//  MPVClient.swift
//  Yattee
//
//  Low-level wrapper around libmpv for video playback.
//

import Foundation
import Libmpv

#if os(macOS)
import OpenGL.GL
#endif

// MARK: - EDL Builder

/// Builds MPV EDL (Edit Decision List) URLs for combining separate video and audio streams.
/// EDL allows MPV to treat multiple streams as a single virtual file with unified caching.
enum EDLBuilder {
    /// Escape URL for EDL format using length-prefix encoding.
    /// Format: %<length>%<url> (e.g., %45%https://example.com/video.mp4)
    /// This is the same format used by mpv's internal ytdl_hook.lua.
    static func escape(_ url: URL) -> String {
        let urlString = url.absoluteString
        return "%\(urlString.count)%\(urlString)"
    }

    /// Build combined EDL string from separate video and audio stream URLs.
    /// The EDL format tells MPV to load both streams together with unified caching.
    ///
    /// Format: edl://!new_stream;!no_clip;!no_chapters;%<video_len>%<video_url>;!new_stream;%<audio_len>%<audio_url>
    ///
    /// Note: Returns a String, not a URL, because the EDL format contains characters
    /// that make it invalid as a Swift URL (e.g., embedded percent signs from YouTube URLs).
    /// MPV accepts this string directly in the loadfile command.
    ///
    /// - Parameters:
    ///   - video: The video stream URL
    ///   - audio: The audio stream URL
    /// - Returns: A combined EDL string for mpv's loadfile command
    static func combinedString(video: URL, audio: URL) -> String {
        "edl://!new_stream;!no_clip;!no_chapters;\(escape(video));!new_stream;\(escape(audio))"
    }
}

// MARK: - MPV Error

enum MPVError: LocalizedError {
    case initializationFailed
    case commandFailed(String)
    case propertyError(String)
    case renderContextFailed

    var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "Failed to initialize MPV"
        case .commandFailed(let cmd):
            return "MPV command failed: \(cmd)"
        case .propertyError(let prop):
            return "MPV property error: \(prop)"
        case .renderContextFailed:
            return "Failed to create MPV render context"
        }
    }
}

// MARK: - MPV Property Observer

/// Cache state information from MPV's demuxer-cache-state property.
struct MPVCacheState: Sendable {
    /// Bytes buffered ahead of current position.
    let forwardBytes: Int64
    /// Total bytes in cache.
    let totalBytes: Int64
    /// Network input rate in bytes per second.
    let inputRate: Int64
    /// Whether end of file is cached.
    let eofCached: Bool
    /// Cache duration in seconds ahead of current position.
    let cacheDuration: Double?
}

/// Version and build information from MPV.
struct MPVVersionInfo: Sendable {
    /// MPV version string (e.g., "mpv 0.37.0").
    let mpvVersion: String?
    /// FFmpeg version string.
    let ffmpegVersion: String?
    /// MPV compilation configuration/flags.
    let configuration: String?
    /// libmpv API version number.
    let apiVersion: UInt
}

protocol MPVClientDelegate: AnyObject {
    func mpvClient(_ client: MPVClient, didUpdateProperty property: String, value: Any?)
    func mpvClient(_ client: MPVClient, didReceiveEvent event: mpv_event_id)
    func mpvClient(_ client: MPVClient, didUpdateCacheState cacheState: MPVCacheState)
    func mpvClientDidEndFile(_ client: MPVClient, reason: MPVEndFileReason)
}

enum MPVEndFileReason {
    case eof
    case stop
    case quit
    case error
    case redirect
    case unknown
}

// MARK: - MPV Client

/// Thread-safe wrapper around libmpv.
/// All mpv operations are performed on a dedicated dispatch queue.
final class MPVClient: @unchecked Sendable {
    // MARK: - Properties

    private var mpv: OpaquePointer?
    private var renderContext: OpaquePointer?
    private let mpvQueue = DispatchQueue(label: "stream.yattee.mpv.client", qos: .userInteractive)
    private var isDestroyed = false

    #if os(macOS)
    /// CGL context for thread-safe OpenGL access (macOS only).
    private var openGLContext: CGLContextObj?
    #endif

    weak var delegate: MPVClientDelegate?

    /// Event loop task
    private var eventLoopTask: Task<Void, Never>?

    /// Semaphore signaled when event loop exits
    private let eventLoopExitSemaphore = DispatchSemaphore(value: 0)

    /// Callback for render updates (called when mpv wants to redraw)
    var onRenderUpdate: (() -> Void)?

    /// Callback for when a new video frame is available (not just any redraw)
    var onVideoFrameReady: (() -> Void)?

    // MARK: - Initialization

    init() {}

    deinit {
        destroy()
    }

    // MARK: - Logging Helpers

    /// Log to LoggingService from any thread (async dispatch to MainActor).
    private func log(_ message: String, details: String? = nil) {
        Task { @MainActor in
            LoggingService.shared.logMPV(message, details: details)
        }
    }

    /// Log debug message to LoggingService from any thread.
    private func logDebug(_ message: String, details: String? = nil) {
        Task { @MainActor in
            LoggingService.shared.logMPVDebug(message, details: details)
        }
    }

    /// Log warning to LoggingService from any thread.
    private func logWarning(_ message: String, details: String? = nil) {
        Task { @MainActor in
            LoggingService.shared.logMPVWarning(message, details: details)
        }
    }

    /// Log error to LoggingService from any thread.
    private func logError(_ message: String, details: String? = nil) {
        Task { @MainActor in
            LoggingService.shared.logMPVError(message)
        }
    }

    // MARK: - Lifecycle

    /// Initialize the MPV instance with default options.
    func initialize() throws {
        var initError: String?

        try mpvQueue.sync {
            guard mpv == nil else {
                logDebug("Already initialized")
                return
            }

            log("Creating handle...")

            // Create MPV handle
            mpv = mpv_create()
            guard mpv != nil else {
                initError = "Failed to create MPV handle"
                throw MPVError.initializationFailed
            }

            log("Handle created, configuring options...")

            // Configure default options
            configureDefaultOptions()

            log("Options configured, initializing...")

            // Initialize MPV
            let result = mpv_initialize(mpv)
            guard result >= 0 else {
                let errorString = String(cString: mpv_error_string(result))
                initError = "MPV initialization failed: \(errorString) (\(result))"
                mpv_destroy(mpv)
                mpv = nil
                throw MPVError.initializationFailed
            }

            log("Initialized, setting up property observers...")

            // Log hwdec diagnostics
            #if os(tvOS)
            if let hwdec = mpv_get_property_string(mpv, "hwdec") {
                logDebug("hwdec: \(String(cString: hwdec))")
                mpv_free(hwdec)
            }
            if let hwdecCodecs = mpv_get_property_string(mpv, "hwdec-codecs") {
                logDebug("hwdec-codecs: \(String(cString: hwdecCodecs))")
                mpv_free(hwdecCodecs)
            }
            if let hwdecInterop = mpv_get_property_string(mpv, "gpu-hwdec-interop") {
                logDebug("gpu-hwdec-interop: \(String(cString: hwdecInterop))")
                mpv_free(hwdecInterop)
            }
            #endif

            // Set up property observers
            setupPropertyObservers()

            log("Starting event loop...")

            // Start event loop
            startEventLoop()

            log("Fully initialized")

            // Log version info
            logVersionInfo()
        }

        // Log errors on main thread after sync block
        if let error = initError {
            Task { @MainActor in
                LoggingService.shared.logMPVError(error)
            }
        }
    }

    /// Log MPV version and build information.
    private func logVersionInfo() {
        guard let mpv, !isDestroyed else { return }

        // Get mpv-version property
        var mpvVersion = "unknown"
        if let cString = mpv_get_property_string(mpv, "mpv-version") {
            mpvVersion = String(cString: cString)
            mpv_free(cString)
        }

        // Get ffmpeg-version property
        var ffmpegVersion = "unknown"
        if let cString = mpv_get_property_string(mpv, "ffmpeg-version") {
            ffmpegVersion = String(cString: cString)
            mpv_free(cString)
        }

        // Get libmpv API version
        let apiVersion = mpv_client_api_version()
        let apiMajor = (apiVersion >> 16) & 0xFFFF
        let apiMinor = apiVersion & 0xFFFF

        log("MPV version info",
            details: "MPV: \(mpvVersion)\nFFmpeg: \(ffmpegVersion)\nAPI: \(apiMajor).\(apiMinor)")
    }

    /// Destroy the MPV instance and release resources.
    func destroy() {
        // First, destroy render context (must happen before mpv is destroyed)
        destroyRenderContext()

        // Mark as destroyed and wake up event loop
        let hasEventLoop: Bool = mpvQueue.sync {
            guard !isDestroyed, mpv != nil else { return false }
            isDestroyed = true

            // Clear any pending operations
            pendingAudioURL = nil

            // Wake up the event loop so it can see isDestroyed and exit
            if let mpv {
                mpv_wakeup(mpv)
            }

            let hasTask = eventLoopTask != nil
            eventLoopTask?.cancel()
            eventLoopTask = nil
            return hasTask
        }

        // Wait for event loop to actually exit before destroying mpv
        if hasEventLoop {
            // Wait up to 500ms for event loop to exit gracefully
            _ = eventLoopExitSemaphore.wait(timeout: .now() + 0.5)
        }

        // Now safe to destroy mpv - event loop has exited
        mpvQueue.sync {
            guard let mpvHandle = mpv else { return }
            mpv_terminate_destroy(mpvHandle)
            mpv = nil
        }
    }

    // MARK: - Configuration

    private func configureDefaultOptions() {
        guard mpv != nil else { return }

        // Video output - use libmpv for render API
        setOptionSync("vo", "libmpv")

        #if targetEnvironment(simulator)
        // Simulator-specific configuration for software rendering
        setOptionSync("hwdec", "no")  // Force software decode (no VideoToolbox in simulator)
        setOptionSync("sw-fast", "yes")  // Enable fast software rendering mode
        // Limit resolution to 720p for better simulator performance
        setOptionSync("vf", "scale=w=min(iw\\,1280):h=min(ih\\,720)")
        #else
        // Hardware decoding - use videotoolbox-copy for correct colors
        // Zero-copy (videotoolbox) causes color space issues with OpenGL ES rendering
        setOptionSync("hwdec", "videotoolbox-copy")

        // Explicitly enable all VideoToolbox-supported codecs for hardware decode
        // MPV default may not include VP9 - we need to explicitly list it
        setOptionSync("hwdec-codecs", "h264,hevc,mpeg1video,mpeg2video,mpeg4,vp9,av1,prores")
        #endif

        // Keep player open after playback ends
        setOptionSync("keep-open", "yes")

        // Start paused - wait for explicit play() call
        // This prevents audio from playing before the UI is ready
        setOptionSync("pause", "yes")

        // Color management
        setOptionSync("target-prim", "bt.709")
        setOptionSync("target-trc", "srgb")

        // Use display-vdrop: drops/repeats frames to match display timing
        // This is lighter weight than display-resample (no interpolation overhead)
        // and handles both hardware and software decode gracefully
        setOptionSync("video-sync", "display-vdrop")

        // Allow frame dropping when decoder can't keep up (essential for software decode)
        // decoder+vo: drop at decoder level first, then at video output if still behind
        setOptionSync("framedrop", "decoder+vo")

        // Audio
        setOptionSync("audio-client-name", "Yattee")
        #if os(iOS) || os(tvOS)
        setOptionSync("ao", "audiounit")
        #elseif os(macOS)
        setOptionSync("ao", "coreaudio")
        #endif

        // Cache settings for network streams
        setOptionSync("cache", "yes")
        setOptionSync("demuxer-max-bytes", "50MiB")
        setOptionSync("demuxer-max-back-bytes", "25MiB")

        // Logging - minimal logging for release builds
        setOptionSync("terminal", "no")
        setOptionSync("msg-level", "all=v")

        // User agent for HTTP requests - use the user's configured setting
        setOptionSync("user-agent", SettingsManager.currentUserAgent())

        // Apply subtitle appearance settings
        applySubtitleSettings()

        // Apply user's custom MPV options (these can override defaults)
        applyCustomOptions()
    }

    /// Apply subtitle appearance settings from user preferences.
    private func applySubtitleSettings() {
        let subtitleSettings = SettingsManager.subtitleSettingsSync()
        let options = subtitleSettings.mpvOptions()
        for (name, value) in options {
            log("Applying subtitle option", details: "\(name)=\(value)")
            setOptionSync(name, value)
        }
    }

    /// Update subtitle settings on a running MPV instance.
    /// Uses mpv_set_property_string which works during playback (unlike mpv_set_option_string).
    func updateSubtitleSettings() {
        mpvQueue.async { [weak self] in
            guard let self, let mpv = self.mpv, !self.isDestroyed else { return }

            let subtitleSettings = SettingsManager.subtitleSettingsSync()
            let options = subtitleSettings.mpvOptions()

            for (name, value) in options {
                self.log("Updating subtitle property", details: "\(name)=\(value)")
                mpv_set_property_string(mpv, name, value)
            }
        }
    }

    /// Apply user-defined custom MPV options from settings.
    /// These are applied after default options and can override them.
    private func applyCustomOptions() {
        let customOptions = SettingsManager.customMPVOptionsSync()
        for (name, value) in customOptions {
            log("Applying custom option", details: "\(name)=\(value)")
            setOptionSync(name, value)
        }
    }

    /// Set option synchronously (for use during initialization on mpvQueue).
    private func setOptionSync(_ name: String, _ value: String) {
        guard let mpv else { return }
        let result = mpv_set_option_string(mpv, name, value)
        if result < 0 {
            logWarning("Failed to set option \(name)=\(value)", details: String(cString: mpv_error_string(result)))
        }
    }

    private func setupPropertyObservers() {
        guard mpv != nil else { return }

        // Observe key properties
        observeProperty("time-pos", format: MPV_FORMAT_DOUBLE)
        observeProperty("duration", format: MPV_FORMAT_DOUBLE)
        observeProperty("pause", format: MPV_FORMAT_FLAG)
        observeProperty("eof-reached", format: MPV_FORMAT_FLAG)
        observeProperty("demuxer-cache-time", format: MPV_FORMAT_DOUBLE)
        observeProperty("demuxer-cache-state", format: MPV_FORMAT_NODE)
        observeProperty("speed", format: MPV_FORMAT_DOUBLE)
        observeProperty("volume", format: MPV_FORMAT_DOUBLE)
        observeProperty("mute", format: MPV_FORMAT_FLAG)
        observeProperty("core-idle", format: MPV_FORMAT_FLAG)
        observeProperty("seeking", format: MPV_FORMAT_FLAG)
        // Cache-related properties for debugging playback start issues
        observeProperty("paused-for-cache", format: MPV_FORMAT_FLAG)
        observeProperty("cache-buffering-state", format: MPV_FORMAT_INT64)
        // Video dimensions for aspect ratio detection
        observeProperty("width", format: MPV_FORMAT_INT64)
        observeProperty("height", format: MPV_FORMAT_INT64)
        // Video FPS for display link frame rate matching (avoid sync fetch on main thread)
        observeProperty("container-fps", format: MPV_FORMAT_DOUBLE)
        // Video codec info for hwdec diagnostics (avoid sync fetch on main thread)
        observeProperty("video-codec", format: MPV_FORMAT_STRING)
        observeProperty("hwdec-current", format: MPV_FORMAT_STRING)
        observeProperty("hwdec-interop", format: MPV_FORMAT_STRING)
    }

    // MARK: - Options

    /// Set an MPV option (must be called before initialize or after load).
    func setOption(_ name: String, _ value: String) {
        mpvQueue.async { [weak self] in
            guard let mpv = self?.mpv else { return }
            mpv_set_option_string(mpv, name, value)
        }
    }

    // MARK: - Playback Control

    /// Load a file/URL for playback.
    /// - Parameters:
    ///   - url: The video URL to play
    ///   - audioURL: Optional separate audio track URL (for video-only streams)
    ///   - httpHeaders: Optional HTTP headers for streaming (cookies, referer, etc.)
    ///   - useEDL: If true and audioURL is provided, combine streams using EDL for unified caching
    ///   - options: Additional MPV options
    func loadFile(_ url: URL, audioURL: URL? = nil, httpHeaders: [String: String]? = nil, useEDL: Bool = true, options: [String] = []) throws {
        try mpvQueue.sync {
            guard mpv != nil, !isDestroyed else {
                throw MPVError.commandFailed("loadfile")
            }

            // Set HTTP headers as a property before loading (if provided)
            // Use MPV_FORMAT_NODE_ARRAY for proper header handling
            if let httpHeaders, !httpHeaders.isEmpty {
                let headerArray = httpHeaders.map { "\($0.key): \($0.value)" }
                logDebug("Setting \(headerArray.count) HTTP headers", details: headerArray.map { String($0.prefix(50)) }.joined(separator: ", "))
                setStringArrayPropertyUnsafe("http-header-fields", headerArray)
            } else {
                // Clear any previously set headers
                setStringArrayPropertyUnsafe("http-header-fields", [])
            }

            // Determine what to load
            // NOTE: EDL mode doesn't work with HTTP headers - the http-header-fields property
            // only applies to the EDL URL itself, not to the embedded stream URLs.
            // When streams require headers (cookies, user-agent, etc.), we must use traditional
            // loadfile + audio-add approach instead of EDL.
            let hasHeaders = httpHeaders != nil && !httpHeaders!.isEmpty
            let shouldUseEDL = useEDL && !hasHeaders
            
            let loadString: String
            if let audioURL, shouldUseEDL {
                // Use EDL to combine video and audio into single virtual file
                // This provides unified caching and better A/V sync
                let edlString = EDLBuilder.combinedString(video: url, audio: audioURL)
                log("loadFile using EDL", details: edlString)
                loadString = edlString
                pendingAudioURL = nil  // No need to add audio separately
            } else {
                // Fall back to loading video first, then adding audio via audio-add
                // This is required when HTTP headers are needed (EDL doesn't support headers on embedded URLs)
                if hasHeaders {
                    log("loadFile (non-EDL due to HTTP headers)", details: url.absoluteString)
                } else {
                    log("loadFile", details: url.absoluteString)
                }
                if let audioURL {
                    logDebug("will add separate audio after load", details: audioURL.absoluteString)
                }
                loadString = url.absoluteString
                pendingAudioURL = audioURL
            }

            var args = ["loadfile", loadString]
            if !options.isEmpty {
                args.append("replace")
                args.append(options.joined(separator: ","))
            }

            log("Command", details: args.joined(separator: " "))
            try commandThrowingUnsafe(args)
        }
    }

    /// Pending audio URL to be added after file loads (accessed only on mpvQueue).
    private var pendingAudioURL: URL?

    /// Add an external audio track. Call this after the file is loaded.
    private func addExternalAudioUnsafe(_ url: URL) {
        // Must be called on mpvQueue
        guard mpv != nil, !isDestroyed else { return }

        logDebug("Adding external audio", details: url.absoluteString)

        // audio-add <url> [<flags> [<title> [<lang>]]]
        // flags: "select" to auto-select, "auto" for default behavior, "cached" for cached
        let args = ["audio-add", url.absoluteString, "select"]
        _ = commandUnsafe(args)
    }

    /// Adds pending audio track if any. Must be called on mpvQueue.
    private func addPendingAudioIfNeeded() {
        guard let audioURL = pendingAudioURL else { return }
        pendingAudioURL = nil
        addExternalAudioUnsafe(audioURL)
    }

    /// Start or resume playback.
    func play() {
        setProperty("pause", false)
    }

    /// Pause playback.
    func pause() {
        setProperty("pause", true)
    }

    /// Stop playback and clear the playlist.
    func stop() {
        command(["stop"])
    }

    /// Seek to a specific time in seconds.
    func seek(to time: Double, mode: String = "absolute") {
        command(["seek", String(time), mode])
    }

    /// Seek to a specific time in seconds asynchronously (non-blocking).
    /// Use this to avoid blocking the calling thread during seeks.
    func seekAsync(to time: Double, mode: String = "absolute") {
        commandAsync(["seek", String(time), mode])
    }

    /// Seek by a relative offset in seconds.
    func seekRelative(_ offset: Double) {
        command(["seek", String(offset), "relative"])
    }

    /// Seek by a relative offset in seconds asynchronously (non-blocking).
    func seekRelativeAsync(_ offset: Double) {
        commandAsync(["seek", String(offset), "relative"])
    }

    // MARK: - Subtitles

    /// Add an external subtitle file.
    /// - Parameters:
    ///   - url: The subtitle URL (VTT, SRT, etc.)
    ///   - select: Whether to automatically select this subtitle
    func addSubtitle(_ url: URL, select: Bool = true) {
        // sub-add <url> [<flags> [<title> [<lang>]]]
        let flags = select ? "select" : "auto"
        command(["sub-add", url.absoluteString, flags])
    }

    /// Add an external subtitle file asynchronously (does not block caller).
    /// Use this for remote URLs to avoid blocking the UI during download.
    /// - Parameters:
    ///   - url: The subtitle URL (VTT, SRT, etc.)
    ///   - select: Whether to automatically select this subtitle
    func addSubtitleAsync(_ url: URL, select: Bool = true) {
        let flags = select ? "select" : "auto"
        commandAsync(["sub-add", url.absoluteString, flags])
    }

    /// Disable subtitles (set sid to "no").
    func disableSubtitles() {
        setProperty("sid", "no")
    }

    /// Enable subtitles by selecting the first track (if any).
    func enableSubtitles() {
        setProperty("sid", "auto")
    }

    /// Remove all external subtitle tracks.
    func removeAllSubtitles() {
        command(["sub-remove"])
    }

    /// Remove all external subtitle tracks asynchronously.
    func removeAllSubtitlesAsync() {
        commandAsync(["sub-remove"])
    }

    // MARK: - Properties

    /// ⚠️ **THREADING WARNING FOR SYNC GETTERS**: The synchronous property getters below
    /// (getFlag, getDouble, getString, getInt, getCacheState, getVersionInfo, getDebugProperties)
    /// use `mpvQueue.sync` which **blocks the calling thread** until the property is fetched.
    ///
    /// **NEVER call these from @MainActor code** - they cause UI hangs (300ms+) that trigger
    /// iOS watchdog warnings. Hang logs show this pattern:
    /// ```
    /// Main Thread → getFlag() → mpvQueue.sync → mpv_get_property() → mp_dispatch_lock() → blocked
    /// ```
    ///
    /// **Safe usage:**
    /// - ✅ From background threads/queues where blocking is acceptable
    /// - ✅ During initialization (before UI is shown)
    /// - ✅ In non-critical paths where 100-500ms delay is acceptable
    ///
    /// **Use async variants instead:**
    /// - From @MainActor code: Use `getFlagAsync()`, `getDoubleAsync()`, etc.
    /// - For frequently accessed properties: Use property observation (delegate callbacks)
    /// - For diagnostics/logging: Use `Task.detached` with async getters
    ///
    /// **Why blocking is necessary:**
    /// libmpv is not thread-safe - all property access must be serialized through `mpvQueue`.
    /// The `sync` dispatch ensures the caller gets the current value, but requires blocking.

    /// Set a property value.
    func setProperty(_ name: String, _ value: Any) {
        mpvQueue.async { [weak self] in
            self?.setPropertyUnsafe(name, value)
        }
    }

    /// Set a property value synchronously. Use when timing is critical.
    func setPropertySync(_ name: String, _ value: Any) {
        mpvQueue.sync { [weak self] in
            self?.setPropertyUnsafe(name, value)
        }
    }

    /// Internal property setter (must be called on mpvQueue).
    private func setPropertyUnsafe(_ name: String, _ value: Any) {
        guard let mpv, !isDestroyed else { return }

        switch value {
        case let boolValue as Bool:
            var flag: Int32 = boolValue ? 1 : 0
            mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &flag)

        case let intValue as Int:
            var int64 = Int64(intValue)
            mpv_set_property(mpv, name, MPV_FORMAT_INT64, &int64)

        case let doubleValue as Double:
            var double = doubleValue
            mpv_set_property(mpv, name, MPV_FORMAT_DOUBLE, &double)

        case let stringValue as String:
            stringValue.withCString { cString in
                var ptr: UnsafePointer<CChar>? = cString
                mpv_set_property(mpv, name, MPV_FORMAT_STRING, &ptr)
            }

        case let stringArray as [String]:
            // For properties like http-header-fields that expect an array of strings
            setStringArrayPropertyUnsafe(name, stringArray)

        default:
            break
        }
    }

    /// Set a string array property using MPV_FORMAT_NODE_ARRAY.
    private func setStringArrayPropertyUnsafe(_ name: String, _ values: [String]) {
        guard let mpv, !isDestroyed else { return }

        // Create array of mpv_node for each string
        var nodeList = values.map { str -> mpv_node in
            var node = mpv_node()
            node.format = MPV_FORMAT_STRING
            // We need to keep the C string alive, so we'll use strdup
            node.u.string = strdup(str)
            return node
        }

        // Create the node array
        var list = mpv_node_list()
        list.num = Int32(nodeList.count)

        nodeList.withUnsafeMutableBufferPointer { buffer in
            list.values = buffer.baseAddress

            var node = mpv_node()
            node.format = MPV_FORMAT_NODE_ARRAY
            withUnsafeMutablePointer(to: &list) { listPtr in
                node.u.list = listPtr
                mpv_set_property(mpv, name, MPV_FORMAT_NODE, &node)
            }
        }

        // Free the strdup'd strings
        for node in nodeList {
            free(node.u.string)
        }
    }

    /// Get a double property value.
    /// **⚠️ BLOCKS CALLING THREAD** - Use getDoubleAsync() from @MainActor code.
    func getDouble(_ name: String) -> Double? {
        mpvQueue.sync {
            guard let mpv, !isDestroyed else { return nil }

            var value: Double = 0
            let result = mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &value)
            return result >= 0 ? value : nil
        }
    }

    /// Get a boolean property value.
    /// **⚠️ BLOCKS CALLING THREAD** - Use getFlagAsync() from @MainActor code.
    func getFlag(_ name: String) -> Bool? {
        mpvQueue.sync {
            guard let mpv, !isDestroyed else { return nil }

            var value: Int32 = 0
            let result = mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &value)
            return result >= 0 ? (value != 0) : nil
        }
    }

    /// Get a string property value.
    /// **⚠️ BLOCKS CALLING THREAD** - Use getStringAsync() from @MainActor code.
    func getString(_ name: String) -> String? {
        mpvQueue.sync {
            guard let mpv, !isDestroyed else { return nil }

            guard let cString = mpv_get_property_string(mpv, name) else {
                return nil
            }
            let string = String(cString: cString)
            mpv_free(cString)
            return string
        }
    }

    /// Get an integer property value.
    /// **⚠️ BLOCKS CALLING THREAD** - Use getIntAsync() from @MainActor code.
    func getInt(_ name: String) -> Int? {
        mpvQueue.sync {
            guard let mpv, !isDestroyed else { return nil }

            var value: Int64 = 0
            let result = mpv_get_property(mpv, name, MPV_FORMAT_INT64, &value)
            return result >= 0 ? Int(value) : nil
        }
    }

    /// Get the demuxer cache state.
    /// **⚠️ BLOCKS CALLING THREAD** - Use getCacheStateAsync() from @MainActor code.
    func getCacheState() -> MPVCacheState? {
        mpvQueue.sync {
            guard let mpv, !isDestroyed else { return nil }

            var node = mpv_node()
            let result = mpv_get_property(mpv, "demuxer-cache-state", MPV_FORMAT_NODE, &node)
            guard result >= 0 else {
                return nil
            }

            defer {
                mpv_free_node_contents(&node)
            }

            return parseCacheStateSync(node)
        }
    }

    /// Get MPV version and build information.
    /// **⚠️ BLOCKS CALLING THREAD** - Use getVersionInfoAsync() from @MainActor code.
    func getVersionInfo() -> MPVVersionInfo? {
        mpvQueue.sync {
            guard let mpv, !isDestroyed else { return nil }

            // Get mpv-version property
            var mpvVersion: String?
            if let cString = mpv_get_property_string(mpv, "mpv-version") {
                mpvVersion = String(cString: cString)
                mpv_free(cString)
            }

            // Get ffmpeg-version property
            var ffmpegVersion: String?
            if let cString = mpv_get_property_string(mpv, "ffmpeg-version") {
                ffmpegVersion = String(cString: cString)
                mpv_free(cString)
            }

            // Get mpv-configuration property (compilation flags)
            var configuration: String?
            if let cString = mpv_get_property_string(mpv, "mpv-configuration") {
                configuration = String(cString: cString)
                mpv_free(cString)
            }

            // Get libmpv API version
            let apiVersion = mpv_client_api_version()

            return MPVVersionInfo(
                mpvVersion: mpvVersion,
                ffmpegVersion: ffmpegVersion,
                configuration: configuration,
                apiVersion: UInt(apiVersion)
            )
        }
    }

    /// Raw debug properties fetched in a single sync block to minimize lock contention.
    struct DebugProperties {
        var videoCodec: String?
        var hwdecCurrent: String?
        var width: Int?
        var height: Int?
        var containerFps: Double?
        var estimatedVfFps: Double?
        var audioCodecName: String?
        var audioSampleRate: Int?
        var audioChannels: Int?
        var frameDropCount: Int?
        var mistimedFrameCount: Int?
        var voDelayedFrameCount: Int?
        var avsync: Double?
        var estimatedFrameNumber: Int?
        var demuxerCacheDuration: Double?
        var fileFormat: String?
        var cacheState: MPVCacheState?
        // tvOS-specific
        var videoSync: String?
        var displayFps: Double?
        var vsyncJitter: Double?
        var videoSpeedCorrection: Double?
        var audioSpeedCorrection: Double?
        var framedrop: String?
    }

    /// Fetch all debug properties in a single sync block to avoid multiple lock acquisitions.
    /// **⚠️ BLOCKS CALLING THREAD** - Use getDebugPropertiesAsync() from @MainActor code.
    func getDebugProperties() -> DebugProperties {
        mpvQueue.sync {
            guard let mpv, !isDestroyed else { return DebugProperties() }

            var props = DebugProperties()

            // Helper functions for property fetching
            func getString(_ name: String) -> String? {
                guard let cString = mpv_get_property_string(mpv, name) else { return nil }
                let string = String(cString: cString)
                mpv_free(cString)
                return string
            }

            func getDouble(_ name: String) -> Double? {
                var value: Double = 0
                let result = mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &value)
                return result >= 0 ? value : nil
            }

            func getInt(_ name: String) -> Int? {
                var value: Int64 = 0
                let result = mpv_get_property(mpv, name, MPV_FORMAT_INT64, &value)
                return result >= 0 ? Int(value) : nil
            }

            // Video info
            props.videoCodec = getString("video-codec")
            props.hwdecCurrent = getString("hwdec-current")
            props.width = getInt("width")
            props.height = getInt("height")
            props.containerFps = getDouble("container-fps")
            props.estimatedVfFps = getDouble("estimated-vf-fps")

            // Audio info
            props.audioCodecName = getString("audio-codec-name")
            props.audioSampleRate = getInt("audio-params/samplerate")
            props.audioChannels = getInt("audio-params/channel-count")

            // Playback stats
            props.frameDropCount = getInt("frame-drop-count")
            props.mistimedFrameCount = getInt("mistimed-frame-count")
            props.voDelayedFrameCount = getInt("vo-delayed-frame-count")
            props.avsync = getDouble("avsync")
            props.estimatedFrameNumber = getInt("estimated-frame-number")

            // Cache/Network
            props.demuxerCacheDuration = getDouble("demuxer-cache-duration")

            // Container
            props.fileFormat = getString("file-format")

            // Cache state (complex property)
            var node = mpv_node()
            if mpv_get_property(mpv, "demuxer-cache-state", MPV_FORMAT_NODE, &node) >= 0 {
                props.cacheState = parseCacheStateSync(node)
                mpv_free_node_contents(&node)
            }

            // Video Sync stats (tvOS)
            #if os(tvOS)
            props.videoSync = getString("video-sync")
            props.displayFps = getDouble("display-fps")
            props.vsyncJitter = getDouble("vsync-jitter")
            props.videoSpeedCorrection = getDouble("video-speed-correction")
            props.audioSpeedCorrection = getDouble("audio-speed-correction")
            props.framedrop = getString("framedrop")
            #endif

            return props
        }
    }

    // MARK: - Async Property Getters (Non-Blocking)

    /// Get a boolean property value asynchronously (non-blocking).
    /// Use this from MainActor code instead of getFlag() to avoid blocking the UI.
    /// - Parameter name: The property name (e.g., "pause", "idle-active")
    /// - Returns: The boolean value, or nil if the property doesn't exist or MPV is destroyed
    func getFlagAsync(_ name: String) async -> Bool? {
        await withCheckedContinuation { continuation in
            mpvQueue.async { [weak self] in
                guard let self, let mpv = self.mpv, !self.isDestroyed else {
                    continuation.resume(returning: nil)
                    return
                }
                var value: Int32 = 0
                let result = mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &value)
                continuation.resume(returning: result >= 0 ? (value != 0) : nil)
            }
        }
    }

    /// Get a double property value asynchronously (non-blocking).
    /// Use this from MainActor code instead of getDouble() to avoid blocking the UI.
    /// - Parameter name: The property name (e.g., "time-pos", "duration")
    /// - Returns: The double value, or nil if the property doesn't exist or MPV is destroyed
    func getDoubleAsync(_ name: String) async -> Double? {
        await withCheckedContinuation { continuation in
            mpvQueue.async { [weak self] in
                guard let self, let mpv = self.mpv, !self.isDestroyed else {
                    continuation.resume(returning: nil)
                    return
                }
                var value: Double = 0
                let result = mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &value)
                continuation.resume(returning: result >= 0 ? value : nil)
            }
        }
    }

    /// Get a string property value asynchronously (non-blocking).
    /// Use this from MainActor code instead of getString() to avoid blocking the UI.
    /// - Parameter name: The property name (e.g., "video-codec", "hwdec-current")
    /// - Returns: The string value, or nil if the property doesn't exist or MPV is destroyed
    func getStringAsync(_ name: String) async -> String? {
        await withCheckedContinuation { continuation in
            mpvQueue.async { [weak self] in
                guard let self, let mpv = self.mpv, !self.isDestroyed else {
                    continuation.resume(returning: nil)
                    return
                }
                guard let cString = mpv_get_property_string(mpv, name) else {
                    continuation.resume(returning: nil)
                    return
                }
                let string = String(cString: cString)
                mpv_free(cString)
                continuation.resume(returning: string)
            }
        }
    }

    /// Get an integer property value asynchronously (non-blocking).
    /// Use this from MainActor code instead of getInt() to avoid blocking the UI.
    /// - Parameter name: The property name (e.g., "width", "height")
    /// - Returns: The integer value, or nil if the property doesn't exist or MPV is destroyed
    func getIntAsync(_ name: String) async -> Int? {
        await withCheckedContinuation { continuation in
            mpvQueue.async { [weak self] in
                guard let self, let mpv = self.mpv, !self.isDestroyed else {
                    continuation.resume(returning: nil)
                    return
                }
                var value: Int64 = 0
                let result = mpv_get_property(mpv, name, MPV_FORMAT_INT64, &value)
                continuation.resume(returning: result >= 0 ? Int(value) : nil)
            }
        }
    }

    /// Get the demuxer cache state asynchronously (non-blocking).
    /// Use this from MainActor code instead of getCacheState() to avoid blocking the UI.
    /// - Returns: The cache state information, or nil if unavailable or MPV is destroyed
    func getCacheStateAsync() async -> MPVCacheState? {
        await withCheckedContinuation { continuation in
            mpvQueue.async { [weak self] in
                guard let self, let mpv = self.mpv, !self.isDestroyed else {
                    continuation.resume(returning: nil)
                    return
                }
                
                var node = mpv_node()
                let result = mpv_get_property(mpv, "demuxer-cache-state", MPV_FORMAT_NODE, &node)
                guard result >= 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let cacheState = self.parseCacheStateSync(node)
                mpv_free_node_contents(&node)
                continuation.resume(returning: cacheState)
            }
        }
    }

    /// Get MPV version and build information asynchronously (non-blocking).
    /// Use this from MainActor code instead of getVersionInfo() to avoid blocking the UI.
    /// - Returns: The version information, or nil if unavailable or MPV is destroyed
    func getVersionInfoAsync() async -> MPVVersionInfo? {
        await withCheckedContinuation { continuation in
            mpvQueue.async { [weak self] in
                guard let self, let mpv = self.mpv, !self.isDestroyed else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Get mpv-version property
                var mpvVersion: String?
                if let cString = mpv_get_property_string(mpv, "mpv-version") {
                    mpvVersion = String(cString: cString)
                    mpv_free(cString)
                }
                
                // Get ffmpeg-version property
                var ffmpegVersion: String?
                if let cString = mpv_get_property_string(mpv, "ffmpeg-version") {
                    ffmpegVersion = String(cString: cString)
                    mpv_free(cString)
                }
                
                // Get mpv-configuration property
                var configuration: String?
                if let cString = mpv_get_property_string(mpv, "mpv-configuration") {
                    configuration = String(cString: cString)
                    mpv_free(cString)
                }
                
                let apiVersion = mpv_client_api_version()
                
                let info = MPVVersionInfo(
                    mpvVersion: mpvVersion,
                    ffmpegVersion: ffmpegVersion,
                    configuration: configuration,
                    apiVersion: UInt(apiVersion)
                )
                continuation.resume(returning: info)
            }
        }
    }

    /// Fetch all debug properties asynchronously in a single operation (non-blocking).
    /// Use this from MainActor code instead of getDebugProperties() to avoid blocking the UI.
    /// This method batches all property fetches into one async operation for efficiency.
    /// - Returns: A DebugProperties struct with all fetched values
    func getDebugPropertiesAsync() async -> DebugProperties {
        await withCheckedContinuation { continuation in
            mpvQueue.async { [weak self] in
                guard let self, let mpv = self.mpv, !self.isDestroyed else {
                    continuation.resume(returning: DebugProperties())
                    return
                }
                
                var props = DebugProperties()
                
                // Helper functions for property fetching
                func getString(_ name: String) -> String? {
                    guard let cString = mpv_get_property_string(mpv, name) else { return nil }
                    let string = String(cString: cString)
                    mpv_free(cString)
                    return string
                }
                
                func getDouble(_ name: String) -> Double? {
                    var value: Double = 0
                    let result = mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &value)
                    return result >= 0 ? value : nil
                }
                
                func getInt(_ name: String) -> Int? {
                    var value: Int64 = 0
                    let result = mpv_get_property(mpv, name, MPV_FORMAT_INT64, &value)
                    return result >= 0 ? Int(value) : nil
                }
                
                // Video info
                props.videoCodec = getString("video-codec")
                props.hwdecCurrent = getString("hwdec-current")
                props.width = getInt("width")
                props.height = getInt("height")
                props.containerFps = getDouble("container-fps")
                props.estimatedVfFps = getDouble("estimated-vf-fps")
                
                // Audio info
                props.audioCodecName = getString("audio-codec-name")
                props.audioSampleRate = getInt("audio-params/samplerate")
                props.audioChannels = getInt("audio-params/channel-count")
                
                // Playback stats
                props.frameDropCount = getInt("frame-drop-count")
                props.mistimedFrameCount = getInt("mistimed-frame-count")
                props.voDelayedFrameCount = getInt("vo-delayed-frame-count")
                props.avsync = getDouble("avsync")
                props.estimatedFrameNumber = getInt("estimated-frame-number")
                
                // Cache/Network
                props.demuxerCacheDuration = getDouble("demuxer-cache-duration")
                
                // Container
                props.fileFormat = getString("file-format")
                
                // Cache state (complex property)
                var node = mpv_node()
                if mpv_get_property(mpv, "demuxer-cache-state", MPV_FORMAT_NODE, &node) >= 0 {
                    props.cacheState = self.parseCacheStateSync(node)
                    mpv_free_node_contents(&node)
                }
                
                // Video Sync stats (tvOS)
                #if os(tvOS)
                props.videoSync = getString("video-sync")
                props.displayFps = getDouble("display-fps")
                props.vsyncJitter = getDouble("vsync-jitter")
                props.videoSpeedCorrection = getDouble("video-speed-correction")
                props.audioSpeedCorrection = getDouble("audio-speed-correction")
                props.framedrop = getString("framedrop")
                #endif
                
                continuation.resume(returning: props)
            }
        }
    }

    /// Parse mpv_node map into MPVCacheState (sync version for use on mpvQueue).
    private func parseCacheStateSync(_ node: mpv_node) -> MPVCacheState? {
        guard node.format == MPV_FORMAT_NODE_MAP,
              let list = node.u.list else { return nil }

        var forwardBytes: Int64 = 0
        var totalBytes: Int64 = 0
        var inputRate: Int64 = 0
        var eofCached = false
        var cacheDuration: Double?

        let count = Int(list.pointee.num)
        for i in 0..<count {
            guard let keyPtr = list.pointee.keys?[i] else { continue }
            let key = String(cString: keyPtr)
            let valueNode = list.pointee.values[i]

            switch key {
            case "fw-bytes":
                if valueNode.format == MPV_FORMAT_INT64 {
                    forwardBytes = valueNode.u.int64
                }
            case "total-bytes":
                if valueNode.format == MPV_FORMAT_INT64 {
                    totalBytes = valueNode.u.int64
                }
            case "raw-input-rate":
                if valueNode.format == MPV_FORMAT_INT64 {
                    inputRate = valueNode.u.int64
                }
            case "eof-cached":
                if valueNode.format == MPV_FORMAT_FLAG {
                    eofCached = valueNode.u.flag != 0
                }
            case "cache-duration":
                if valueNode.format == MPV_FORMAT_DOUBLE {
                    cacheDuration = valueNode.u.double_
                }
            default:
                break
            }
        }

        return MPVCacheState(
            forwardBytes: forwardBytes,
            totalBytes: totalBytes,
            inputRate: inputRate,
            eofCached: eofCached,
            cacheDuration: cacheDuration
        )
    }

    // MARK: - Property Observation

    private func observeProperty(_ name: String, format: mpv_format) {
        guard let mpv else { return }
        mpv_observe_property(mpv, 0, name, format)
    }

    // MARK: - Commands

    /// Send a command to MPV (public, acquires lock).
    @discardableResult
    func command(_ args: [String]) -> Bool {
        mpvQueue.sync {
            commandUnsafe(args)
        }
    }

    /// Send a command to MPV asynchronously using mpv_command_async.
    /// This returns immediately and doesn't block the mpvQueue during execution.
    /// Use this for commands that may take time (e.g., loading remote subtitles).
    func commandAsync(_ args: [String]) {
        mpvQueue.async { [weak self] in
            guard let self, let mpv = self.mpv, !self.isDestroyed else { return }

            self.logDebug("Async command", details: args.joined(separator: " "))

            // Convert strings to C strings
            var cStrings = args.map { strdup($0) }
            cStrings.append(nil)

            // Use mpv_command_async which returns immediately
            cStrings.withUnsafeMutableBufferPointer { buffer in
                var constPtrs = buffer.map { UnsafePointer($0) }
                // Use @discardableResult pattern - result type is Void so we can just call it
                constPtrs.withUnsafeMutableBufferPointer { constBuffer in
                    // reply_userdata 0 means we don't care about the result
                    _ = mpv_command_async(mpv, 0, constBuffer.baseAddress)
                }
            }

            // Free the strings
            for ptr in cStrings where ptr != nil {
                free(ptr)
            }
        }
    }

    /// Send a command to MPV without locking (must be called on mpvQueue).
    private func commandUnsafe(_ args: [String]) -> Bool {
        guard let mpv, !isDestroyed else {
            logWarning("Command failed: not initialized or destroyed")
            return false
        }

        logDebug("Command", details: args.joined(separator: " "))

        // Convert strings to C strings
        var cStrings = args.map { strdup($0) }
        cStrings.append(nil)

        // Create array of const pointers for mpv_command
        let result = cStrings.withUnsafeMutableBufferPointer { buffer -> Int32 in
            // Cast mutable pointers to const pointers
            var constPtrs = buffer.map { UnsafePointer($0) }
            return constPtrs.withUnsafeMutableBufferPointer { constBuffer in
                mpv_command(mpv, constBuffer.baseAddress)
            }
        }

        // Free the strings
        for ptr in cStrings where ptr != nil {
            free(ptr)
        }

        if result < 0 {
            let errorString = String(cString: mpv_error_string(result))
            logWarning("Command '\(args.first ?? "")' failed", details: "\(errorString) (\(result))")
        }

        return result >= 0
    }

    /// Send a command to MPV, throwing on failure (must be called on mpvQueue).
    private func commandThrowingUnsafe(_ args: [String]) throws {
        let success = commandUnsafe(args)
        if !success {
            throw MPVError.commandFailed(args.joined(separator: " "))
        }
    }

    // MARK: - Event Loop

    private func startEventLoop() {
        eventLoopTask = Task.detached(priority: .high) { [weak self] in
            self?.runEventLoop()
        }
    }

    private func runEventLoop() {
        defer {
            // Signal that event loop has exited
            eventLoopExitSemaphore.signal()
        }

        while !Task.isCancelled && !isDestroyed {
            guard let mpv else { break }

            // Wait for events with a short timeout
            let event = mpv_wait_event(mpv, 0.1)
            guard let event else { continue }

            let eventId = event.pointee.event_id

            // Exit on shutdown
            if eventId == MPV_EVENT_SHUTDOWN {
                break
            }

            // Skip none events
            if eventId == MPV_EVENT_NONE {
                continue
            }

            // Process event
            processEvent(event.pointee)
        }
    }

    private func processEvent(_ event: mpv_event) {
        let eventId = event.event_id

        switch eventId {
        case MPV_EVENT_PROPERTY_CHANGE:
            if let data = event.data {
                let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
                handlePropertyChange(property)
            }

         case MPV_EVENT_END_FILE:
            if let data = event.data {
                let endFile = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                let reason = mapEndFileReason(endFile.reason)
                
                // Log detailed error information when file load fails
                if endFile.reason == MPV_END_FILE_REASON_ERROR {
                    let errorCode = endFile.error
                    let errorString = String(cString: mpv_error_string(errorCode))
                    logError("End file with error", details: "code=\(errorCode), message=\(errorString)")
                    
                    // Also try to get more detailed error from mpv properties
                    Task { @MainActor in
                        LoggingService.shared.logMPVError("MPV end-file error: \(errorString) (code: \(errorCode))")
                    }
                }
                
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.delegate?.mpvClientDidEndFile(self, reason: reason)
                }
            }

        case MPV_EVENT_FILE_LOADED:
            // Add pending external audio track after file is loaded (dispatch to mpvQueue for thread safety)
            mpvQueue.async { [weak self] in
                self?.addPendingAudioIfNeeded()
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.delegate?.mpvClient(self, didReceiveEvent: eventId)
            }

        case MPV_EVENT_PLAYBACK_RESTART, MPV_EVENT_SEEK:
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.delegate?.mpvClient(self, didReceiveEvent: eventId)
            }

        default:
            break
        }
    }

    private func handlePropertyChange(_ property: mpv_event_property) {
        let name = String(cString: property.name)
        var value: Any?

        switch property.format {
        case MPV_FORMAT_DOUBLE:
            if let ptr = property.data {
                value = ptr.assumingMemoryBound(to: Double.self).pointee
            }

        case MPV_FORMAT_FLAG:
            if let ptr = property.data {
                let flag = ptr.assumingMemoryBound(to: Int32.self).pointee
                value = flag != 0
            }

        case MPV_FORMAT_INT64:
            if let ptr = property.data {
                value = ptr.assumingMemoryBound(to: Int64.self).pointee
            }

        case MPV_FORMAT_STRING:
            if let ptr = property.data {
                let cString = ptr.assumingMemoryBound(to: UnsafePointer<CChar>.self).pointee
                value = String(cString: cString)
            }

        case MPV_FORMAT_NODE:
            // Handle demuxer-cache-state specially
            if name == "demuxer-cache-state", let ptr = property.data {
                let node = ptr.assumingMemoryBound(to: mpv_node.self).pointee
                if let cacheState = parseCacheState(node) {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.delegate?.mpvClient(self, didUpdateCacheState: cacheState)
                    }
                }
                return
            }

        case MPV_FORMAT_NONE:
            // Property unavailable
            break

        default:
            break
        }

        let capturedValue = value
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.mpvClient(self, didUpdateProperty: name, value: capturedValue)
        }
    }

    /// Parse mpv_node map into MPVCacheState.
    private func parseCacheState(_ node: mpv_node) -> MPVCacheState? {
        guard node.format == MPV_FORMAT_NODE_MAP,
              let list = node.u.list else { return nil }

        var forwardBytes: Int64 = 0
        var totalBytes: Int64 = 0
        var inputRate: Int64 = 0
        var eofCached = false
        var cacheDuration: Double?

        let count = Int(list.pointee.num)
        for i in 0..<count {
            guard let keyPtr = list.pointee.keys?[i] else { continue }
            let key = String(cString: keyPtr)
            let valueNode = list.pointee.values[i]

            switch key {
            case "fw-bytes":
                if valueNode.format == MPV_FORMAT_INT64 {
                    forwardBytes = valueNode.u.int64
                }
            case "total-bytes":
                if valueNode.format == MPV_FORMAT_INT64 {
                    totalBytes = valueNode.u.int64
                }
            case "raw-input-rate":
                if valueNode.format == MPV_FORMAT_INT64 {
                    inputRate = valueNode.u.int64
                }
            case "eof-cached":
                if valueNode.format == MPV_FORMAT_FLAG {
                    eofCached = valueNode.u.flag != 0
                }
            case "cache-duration":
                if valueNode.format == MPV_FORMAT_DOUBLE {
                    cacheDuration = valueNode.u.double_
                }
            default:
                break
            }
        }

        return MPVCacheState(
            forwardBytes: forwardBytes,
            totalBytes: totalBytes,
            inputRate: inputRate,
            eofCached: eofCached,
            cacheDuration: cacheDuration
        )
    }

    private func mapEndFileReason(_ reason: mpv_end_file_reason) -> MPVEndFileReason {
        switch reason {
        case MPV_END_FILE_REASON_EOF:
            return .eof
        case MPV_END_FILE_REASON_STOP:
            return .stop
        case MPV_END_FILE_REASON_QUIT:
            return .quit
        case MPV_END_FILE_REASON_ERROR:
            return .error
        case MPV_END_FILE_REASON_REDIRECT:
            return .redirect
        default:
            return .unknown
        }
    }

    // MARK: - Render Context

    /// Get the MPV handle for render context creation.
    /// Must be called on mpvQueue.
    var mpvHandle: OpaquePointer? {
        mpvQueue.sync { mpv }
    }

    /// Create a render context for OpenGL rendering.
    /// - Parameter getProcAddress: Function to get OpenGL proc addresses
    /// - Returns: Whether creation succeeded
    func createRenderContext(getProcAddress: @escaping @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?) -> Bool {
        mpvQueue.sync {
            guard let mpv, renderContext == nil else {
                logWarning("Cannot create render context", details: "mpv=\(self.mpv != nil), renderContext=\(self.renderContext != nil)")
                MPVLogging.warn("createRenderContext: precondition failed",
                    details: "mpv:\(self.mpv != nil) renderContext:\(self.renderContext != nil)")
                return false
            }

            log("Creating OpenGL render context...")
            MPVLogging.log("createRenderContext: starting")

            // Set up OpenGL parameters
            var apiType = MPV_RENDER_API_TYPE_OPENGL
            var glInitParams = mpv_opengl_init_params(
                get_proc_address: getProcAddress,
                get_proc_address_ctx: nil
            )

            var ctx: OpaquePointer?
            let result = withUnsafeMutablePointer(to: &apiType) { apiTypePtr in
                withUnsafeMutablePointer(to: &glInitParams) { glInitParamsPtr in
                    var params: [mpv_render_param] = [
                        mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiTypePtr),
                        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: glInitParamsPtr),
                        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                    ]
                    return params.withUnsafeMutableBufferPointer { paramsPtr in
                        mpv_render_context_create(&ctx, mpv, paramsPtr.baseAddress)
                    }
                }
            }

            if result < 0 {
                let errorString = String(cString: mpv_error_string(result))
                logError("Failed to create render context", details: "\(errorString) (\(result))")
                MPVLogging.warn("createRenderContext: FAILED", details: "\(errorString) (\(result))")
                return false
            }

            renderContext = ctx
            log("Render context created successfully")
            MPVLogging.log("createRenderContext: success")

            // Set up render update callback
            if let ctx = renderContext {
                let clientPtr = Unmanaged.passUnretained(self).toOpaque()
                mpv_render_context_set_update_callback(ctx, { clientPtr in
                    guard let clientPtr else { return }
                    let client = Unmanaged<MPVClient>.fromOpaque(clientPtr).takeUnretainedValue()

                    #if os(macOS)
                    // On macOS with CAOpenGLLayer, don't call mpv_render_context_update() here!
                    // That function clears the frame-ready flag after returning it.
                    // If we call it here, then canDraw() will call it again and get 0.
                    // Instead, just notify the layer to display - canDraw() will check the flag.
                    client.onRenderUpdate?()
                    #else
                    // On iOS/tvOS, check if this update includes an actual video frame.
                    // This is needed for PiP frame capture which relies on onVideoFrameReady.
                    client.mpvQueue.async {
                        guard let renderCtx = client.renderContext else { return }
                        let flags = mpv_render_context_update(renderCtx)
                        let hasVideoFrame = flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0

                        // Always notify for general redraw
                        client.onRenderUpdate?()

                        // Notify specifically when there's a video frame
                        if hasVideoFrame {
                            client.onVideoFrameReady?()
                        }
                    }
                    #endif
                }, clientPtr)
            }

            return true
        }
    }

    /// Render a frame to the current OpenGL framebuffer.
    /// - Parameters:
    ///   - fbo: Framebuffer object ID (0 for default)
    ///   - width: Render width in pixels
    ///   - height: Render height in pixels
    /// - Note: This may trigger a priority inversion warning because MPV's internal
    ///   threads run at default QoS. This is unavoidable when using mpv_render_context_render.
    func render(fbo: Int32, width: Int32, height: Int32) {
        mpvQueue.sync {
            guard let renderContext, !isDestroyed else {
                // Log when render is skipped to help diagnose black screen issues
                MPVLogging.warn("render: skipped",
                    details: "ctx:\(renderContext != nil) destroyed:\(isDestroyed)")
                return
            }

            // GL_RGBA8 = 0x8058
            var fboData = mpv_opengl_fbo(
                fbo: fbo,
                w: width,
                h: height,
                internal_format: 0x8058
            )

            var flipY: Int32 = 1

            withUnsafeMutablePointer(to: &fboData) { fboPtr in
                withUnsafeMutablePointer(to: &flipY) { flipPtr in
                    var params: [mpv_render_param] = [
                        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
                        mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipPtr),
                        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                    ]
                    _ = params.withUnsafeMutableBufferPointer { paramsPtr in
                        mpv_render_context_render(renderContext, paramsPtr.baseAddress)
                    }
                }
            }
        }
    }

    /// Create a render context for software rendering (CPU-based, for simulator).
    /// - Returns: Whether creation succeeded
    func createSoftwareRenderContext() -> Bool {
        mpvQueue.sync {
            guard let mpv, renderContext == nil else {
                logWarning("Cannot create software render context", details: "mpv=\(self.mpv != nil), renderContext=\(self.renderContext != nil)")
                MPVLogging.warn("createSoftwareRenderContext: precondition failed",
                    details: "mpv:\(self.mpv != nil) renderContext:\(self.renderContext != nil)")
                return false
            }

            log("Creating software render context...")
            MPVLogging.log("createSoftwareRenderContext: starting")

            // Set up software rendering API type
            var apiType = MPV_RENDER_API_TYPE_SW
            
            var ctx: OpaquePointer?
            let result = withUnsafeMutablePointer(to: &apiType) { apiTypePtr in
                var params: [mpv_render_param] = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiTypePtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                ]
                return params.withUnsafeMutableBufferPointer { paramsPtr in
                    mpv_render_context_create(&ctx, mpv, paramsPtr.baseAddress)
                }
            }

            if result < 0 {
                let errorString = String(cString: mpv_error_string(result))
                logError("Failed to create software render context", details: "\(errorString) (\(result))")
                MPVLogging.warn("createSoftwareRenderContext: FAILED", details: "\(errorString) (\(result))")
                return false
            }

            renderContext = ctx
            log("Software render context created successfully")
            MPVLogging.log("createSoftwareRenderContext: success")

            // Set up render update callback
            // Software rendering is only used on iOS/tvOS simulator, so use the full callback
            if let ctx = renderContext {
                let clientPtr = Unmanaged.passUnretained(self).toOpaque()
                mpv_render_context_set_update_callback(ctx, { clientPtr in
                    guard let clientPtr else { return }
                    let client = Unmanaged<MPVClient>.fromOpaque(clientPtr).takeUnretainedValue()

                    // Check if this update includes an actual video frame
                    client.mpvQueue.async {
                        guard let renderCtx = client.renderContext else { return }
                        let flags = mpv_render_context_update(renderCtx)
                        let hasVideoFrame = flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0

                        // Always notify for general redraw
                        client.onRenderUpdate?()

                        // Notify specifically when there's a video frame
                        if hasVideoFrame {
                            client.onVideoFrameReady?()
                        }
                    }
                }, clientPtr)
            }

            return true
        }
    }

    /// Render a frame to a software buffer (CPU-based rendering).
    /// - Parameters:
    ///   - buffer: Pointer to the pixel buffer (RGBA format)
    ///   - width: Render width in pixels
    ///   - height: Render height in pixels
    ///   - stride: Bytes per line (row stride)
    /// - Returns: true if a frame was rendered, false otherwise
    @discardableResult
    func renderSoftware(buffer: UnsafeMutableRawPointer, width: Int32, height: Int32, stride: Int) -> Bool {
        mpvQueue.sync {
            guard let renderContext, !isDestroyed else {
                return false
            }
            
            // Check if there's a frame ready to render
            let updateFlags = mpv_render_context_update(renderContext)
            let hasFrame = (updateFlags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue)) != 0
            
            if !hasFrame {
                // No frame ready, skip rendering
                return false
            }
            
            // MPV software rendering requires:
            // - MPV_RENDER_PARAM_SW_SIZE: int[2] array with [width, height]
            // - MPV_RENDER_PARAM_SW_FORMAT: C string with format name
            // - MPV_RENDER_PARAM_SW_STRIDE: size_t* pointing to stride value
            // - MPV_RENDER_PARAM_SW_POINTER: void* to pixel buffer
            
            // Stride as size_t (UInt on 64-bit)
            var strideValue: size_t = size_t(stride)
            
            // Format string - "rgb0" means RGB with padding byte (RGBX), which matches our RGBA buffer
            let format = "rgb0"
            
            // Create a contiguous buffer for the size array
            let sizeBuffer = UnsafeMutableBufferPointer<Int32>.allocate(capacity: 2)
            defer { sizeBuffer.deallocate() }
            sizeBuffer[0] = width
            sizeBuffer[1] = height
            
            let result: Int32 = format.withCString { formatPtr in
                withUnsafeMutablePointer(to: &strideValue) { stridePtr in
                    var params: [mpv_render_param] = [
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: sizeBuffer.baseAddress),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: UnsafeMutableRawPointer(mutating: formatPtr)),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: stridePtr),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: buffer),
                        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                    ]
                    
                    return mpv_render_context_render(renderContext, &params)
                }
            }
            
            if result < 0 {
                let errorStr = String(cString: mpv_error_string(result))
                MPVLogging.log("renderSoftware: FAILED - error=\(result) (\(errorStr))")
                return false
            }
            
            return true
        }
    }

    /// Report that the next frame should be rendered.
    func reportRenderUpdate() {
        mpvQueue.async { [weak self] in
            guard let self, let renderContext = self.renderContext, !self.isDestroyed else { return }
            let flags = mpv_render_context_update(renderContext)
            if flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 {
                self.onRenderUpdate?()
            }
        }
    }

    /// Destroy the render context.
    func destroyRenderContext() {
        mpvQueue.sync {
            guard let ctx = renderContext else {
                MPVLogging.log("destroyRenderContext: no context to destroy")
                return
            }
            MPVLogging.log("destroyRenderContext: destroying")
            mpv_render_context_free(ctx)
            renderContext = nil
            MPVLogging.log("destroyRenderContext: complete")
        }
    }

    /// Whether the render context is initialized.
    var hasRenderContext: Bool {
        mpvQueue.sync { renderContext != nil }
    }

    // MARK: - macOS OpenGL Context Management

    #if os(macOS)
    /// Store the CGL context for locking during render operations.
    func setOpenGLContext(_ ctx: CGLContextObj) {
        mpvQueue.sync {
            openGLContext = ctx
        }
    }

    /// Lock the OpenGL context and make it current (call before GL operations from other threads).
    func lockAndSetOpenGLContext() {
        guard let ctx = openGLContext else { return }
        CGLLockContext(ctx)
        CGLSetCurrentContext(ctx)
    }

    /// Unlock the OpenGL context.
    func unlockOpenGLContext() {
        guard let ctx = openGLContext else { return }
        CGLUnlockContext(ctx)
    }
    #endif

    // MARK: - Frame Timing

    /// Report that a frame was swapped/presented (for vsync timing).
    func reportSwap() {
        mpvQueue.async { [weak self] in
            guard let ctx = self?.renderContext else { return }
            mpv_render_context_report_swap(ctx)
        }
    }

    /// Check if MPV has a frame ready to render (non-blocking).
    /// This is safe to call from any thread - mpv's render context API is thread-safe.
    func shouldRenderUpdateFrame() -> Bool {
        // Don't use mpvQueue.sync here - it can cause deadlocks when called from render queue
        // mpv_render_context_update is documented as thread-safe
        guard let ctx = renderContext, !isDestroyed else { return false }
        let flags = mpv_render_context_update(ctx)
        return flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0
    }

    /// Get the render context directly (for thread-safe mpv render operations).
    var mpvRenderContext: OpaquePointer? {
        renderContext
    }

    // MARK: - Rendering with Depth

    /// Render a frame to the current OpenGL framebuffer with specified color depth.
    /// - Parameters:
    ///   - fbo: Framebuffer object ID
    ///   - width: Render width in pixels
    ///   - height: Render height in pixels
    ///   - depth: Color depth (8 or 16 for 10-bit)
    func renderWithDepth(fbo: Int32, width: Int32, height: Int32, depth: Int32) {
        mpvQueue.sync {
            guard let renderContext, !isDestroyed else {
                MPVLogging.warn("renderWithDepth: skipped",
                    details: "ctx:\(renderContext != nil) destroyed:\(isDestroyed)")
                return
            }

            // GL_RGBA8 = 0x8058
            var fboData = mpv_opengl_fbo(
                fbo: fbo,
                w: width,
                h: height,
                internal_format: 0x8058
            )

            var flipY: Int32 = 1
            var bufferDepth = depth

            withUnsafeMutablePointer(to: &fboData) { fboPtr in
                withUnsafeMutablePointer(to: &flipY) { flipPtr in
                    withUnsafeMutablePointer(to: &bufferDepth) { depthPtr in
                        var params: [mpv_render_param] = [
                            mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
                            mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipPtr),
                            mpv_render_param(type: MPV_RENDER_PARAM_DEPTH, data: depthPtr),
                            mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                        ]
                        _ = params.withUnsafeMutableBufferPointer { paramsPtr in
                            mpv_render_context_render(renderContext, paramsPtr.baseAddress)
                        }
                    }
                }
            }
        }
    }
}
