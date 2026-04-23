//
//  MPVBackend.swift
//  Yattee
//
//  MPV-based player backend supporting all video formats.
//

import Foundation
import AVFoundation
import SwiftUI
import Combine
import Libmpv
import CoreMedia
import CoreVideo

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// MPV-based player backend implementation.
/// Supports all video formats including VP9, AV1, and DASH.
@MainActor
final class MPVBackend: PlayerBackend {
    // MARK: - PlayerBackend Properties

    let backendType: PlayerBackendType = .mpv

    weak var delegate: PlayerBackendDelegate?

    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var bufferedTime: TimeInterval = 0
    private(set) var isReady: Bool = false
    private(set) var isPlaying: Bool = false
    private(set) var hasReachedEOF: Bool = false

    var rate: Float {
        get { _rate }
        set {
            _rate = newValue
            mpvClient?.setProperty("speed", Double(newValue))
        }
    }

    var volume: Float {
        get { _volume }
        set {
            _volume = newValue
            mpvClient?.setProperty("volume", Double(newValue * 100))
        }
    }

    var isMuted: Bool {
        get { _isMuted }
        set {
            _isMuted = newValue
            mpvClient?.setProperty("mute", newValue)
        }
    }

    /// Panscan value (0.0 = aspect fit with black bars, 1.0 = aspect fill/crop)
    var panscan: Double {
        get { _panscan }
        set {
            _panscan = max(0, min(1, newValue))
            mpvClient?.setProperty("panscan", _panscan)
        }
    }

    var supportedFormats: Set<StreamFormat> {
        Set(StreamFormat.allCases) // MPV supports all formats
    }

    // MARK: - Public Properties

    /// MPV version and build information (available after initialization).
    private(set) var versionInfo: MPVVersionInfo?

    // MARK: - Private Properties

    private var mpvClient: MPVClient?
    #if os(macOS)
    private var renderView: MPVOGLView?
    #elseif targetEnvironment(simulator) && (os(iOS) || os(tvOS))
    private var renderView: MPVSoftwareRenderView?
    #else
    private var renderView: MPVRenderView?
    #endif

    private var _rate: Float = 1.0
    private var _volume: Float = 1.0
    private var _isMuted: Bool = false
    private var _panscan: Double = 0.0

    private var currentStream: Stream?
    private var currentAudioStream: Stream?
    private var currentCaption: Caption?
    private var pendingAutoplay: Bool = false

    // Retry mechanism: 4 attempts with increasing timeouts and delays
    // Attempt 1: 3s timeout, 1s delay | Attempt 2: 3s timeout, 3s delay
    // Attempt 3: 10s timeout, 5s delay | Attempt 4: 10s timeout, fail
    private var retryCount = 0
    private let retryDelays: [TimeInterval] = [1, 3, 5]  // Delays between attempts (3 delays = 4 attempts)
    private let loadTimeouts: [TimeInterval] = [3, 3, 10, 10]  // Timeout per attempt
    private var isInitialLoading = false  // Prevents event handler from interfering during load
    private var currentLoadingID: UUID?   // Tracks current load operation for cancellation
    private var isWaitingForExternalAudio = false  // True when waiting for external audio track to load

    // Buffer stall detection - triggers stream refresh when buffer stuck at 0% for too long
    private var bufferStallStartTime: Date?
    private let bufferStallTimeout: TimeInterval = 30  // Trigger refresh after 30 seconds of stall
    private var bufferStallCheckTask: Task<Void, Never>?

    // Video dimensions for aspect ratio detection
    private var videoWidth: Int = 0
    private var videoHeight: Int = 0
    // Cached video FPS to avoid sync fetch on main thread
    private var containerFps: Double = 0
    // Cached cache state to avoid sync fetch on main thread
    private var demuxerCacheTime: Double = 0
    private var cacheBufferingState: Int = 0
    private var pausedForCache: Bool = false
    // Cached codec info for hwdec diagnostics
    private var videoCodec: String = ""
    private var hwdecCurrent: String = ""
    private var hwdecInterop: String = ""
    
    // Async initialization tracking
    private var setupTask: Task<Void, Error>?
    private(set) var isSetupComplete = false
    private let setupStartTime = Date()

    #if os(iOS)
    #if targetEnvironment(simulator)
    private var _playerView: MPVSoftwareRenderView?
    #else
    private var _playerView: MPVRenderView?
    #endif
    var playerView: UIView? { _playerView }

    // PiP support using AVSampleBufferDisplayLayer bridge
    private var pipBridge: MPVPiPBridge?

    /// Whether PiP is currently active.
    var isPiPActive: Bool { pipBridge?.isPiPActive ?? false }

    /// Whether PiP is possible.
    var isPiPPossible: Bool { pipBridge?.isPiPPossible ?? false }

    /// Callback for when user wants to restore from PiP to main app.
    /// Set by PlayerService to expand the player sheet.
    var onRestoreFromPiP: (() async -> Void)?

    /// Callback for when PiP starts.
    /// Set by PlayerService to collapse the player sheet.
    var onPiPDidStart: (() -> Void)?

    /// Pause video rendering (for smooth panscan animation)
    func pauseRendering() {
        MPVLogging.log("MPVBackend.pauseRendering called")
        _playerView?.pauseRendering()
    }

    /// Resume video rendering
    func resumeRendering() {
        MPVLogging.log("MPVBackend.resumeRendering called")
        _playerView?.resumeRendering()
    }
    #elseif os(tvOS)
    #if targetEnvironment(simulator)
    private var _playerView: MPVSoftwareRenderView?
    #else
    private var _playerView: MPVRenderView?
    #endif
    var playerView: UIView? { _playerView }
    #elseif os(macOS)
    private var _playerView: MPVOGLView?
    var playerView: NSView? { _playerView }

    // PiP support using AVSampleBufferDisplayLayer bridge
    private var pipBridge: MPVPiPBridge?

    /// Whether PiP is currently active.
    var isPiPActive: Bool { pipBridge?.isPiPActive ?? false }

    /// Whether PiP is possible.
    var isPiPPossible: Bool { pipBridge?.isPiPPossible ?? false }

    /// Callback for when user wants to restore from PiP to main app.
    var onRestoreFromPiP: (() async -> Void)?

    /// Callback for when PiP starts.
    var onPiPDidStart: (() -> Void)?

    /// Callback for when PiP stops without restore (user clicked close button in PiP).
    var onPiPDidStopWithoutRestore: (() -> Void)?

    /// Whether PiP setup has been completed
    private var isPiPSetUp = false

    /// Reference to player state for updating PiP availability
    private weak var pipPlayerState: PlayerState?

    /// Reference to container view for updating layer frame
    private weak var pipContainerView: NSView?

    /// Pause video rendering
    func pauseRendering() {
        MPVLogging.log("MPVBackend.pauseRendering called")
        _playerView?.pauseRendering()
    }

    /// Resume video rendering
    func resumeRendering() {
        MPVLogging.log("MPVBackend.resumeRendering called")
        _playerView?.resumeRendering()
    }
    #endif

    // MARK: - Initialization

    init() {
        // Don't call setupMPV() here - it will be called via beginSetup()
        // This makes init() fast and non-blocking
    }

    deinit {
        MainActor.assumeIsolated {
            cleanup()
        }
    }
    
    /// Begin async initialization (non-blocking).
    /// Call this immediately after creating the backend to start setup in background.
    func beginSetup() {
        guard setupTask == nil else {
            MPVLogging.log("MPVBackend.beginSetup: already started")
            return
        }
        
        MPVLogging.log("MPVBackend.beginSetup: starting async setup")
        
        setupTask = Task { @MainActor in
            await setupMPVAsync()
        }
    }
    
    /// Wait for setup to complete.
    /// Call this before loading streams to ensure backend is ready.
    func waitForSetup() async throws {
        guard let task = setupTask else {
            // Not started yet - begin now
            MPVLogging.log("MPVBackend.waitForSetup: setup not started, beginning now")
            beginSetup()
            guard let task = setupTask else {
                throw MPVRenderError.openGLSetupFailed
            }
            try await task.value
            return
        }
        try await task.value
    }

    // MARK: - Setup

    /// Async setup - moves heavy OpenGL initialization off main thread.
    private func setupMPVAsync() async {
        let startTime = Date()
        MPVLogging.log("setupMPVAsync: starting")

        // Create MPV client (fast, no blocking)
        let client = MPVClient()
        client.delegate = self
        mpvClient = client

        // Create render view (fast on main thread)
        #if os(macOS)
        let view = MPVOGLView()
        renderView = view
        _playerView = view
        MPVLogging.log("setupMPVAsync: macOS render view created")
        #elseif os(iOS)
        #if targetEnvironment(simulator)
        // Use software rendering in simulator (OpenGL ES not available)
        let view = MPVSoftwareRenderView()
        renderView = view
        _playerView = view
        MPVLogging.log("setupMPVAsync: software render view created (iOS simulator)")
        #else
        let view = MPVRenderView()
        renderView = view
        _playerView = view
        MPVLogging.log("setupMPVAsync: OpenGL render view created (iOS device)")
        #endif
        #elseif os(tvOS)
        #if targetEnvironment(simulator)
        // Use software rendering in simulator (OpenGL ES not available)
        let view = MPVSoftwareRenderView()
        renderView = view
        _playerView = view
        MPVLogging.log("setupMPVAsync: software render view created (tvOS simulator)")
        #else
        let view = MPVRenderView()
        renderView = view
        _playerView = view
        MPVLogging.log("setupMPVAsync: OpenGL render view created (tvOS device)")
        #endif
        #endif

        // Set up first-frame callback for accurate ready detection
        view.onFirstFrameRendered = { [weak self] in
            self?.handleFirstFrameRendered()
        }

        #if os(iOS)
        // Set up window callback for PiP setup (view needs to be in window for PiP)
        view.onDidMoveToWindow = { [weak self] containerView in
            guard let self, !self.isPiPSetUp, self.pipPlayerState != nil else { return }
            // Store container reference for updating layer frame after layout
            self.pipContainerView = containerView
            // Complete PiP setup now that view is in a window
            self.setupPiP(in: containerView)
            self.isPiPSetUp = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                // Update sampleBufferLayer frame now that container has been laid out
                if let containerView = self?.pipContainerView, containerView.bounds.size != .zero {
                    self?.pipBridge?.updateLayerFrame(containerView.bounds)
                }
                self?.pipPlayerState?.isPiPPossible = self?.isPiPPossible ?? false
            }
        }
        #endif

        // Initialize MPV and setup render view (HEAVY WORK - now async)
        do {
            MPVLogging.log("setupMPVAsync: initializing client")
            try client.initialize()
            
            MPVLogging.log("setupMPVAsync: setting up render view (OpenGL)")
            let glSetupStart = Date()
            try await view.setupAsync(with: client) // NEW: async version moves OpenGL off main thread
            let glSetupTime = Date().timeIntervalSince(glSetupStart)
            MPVLogging.log("setupMPVAsync: OpenGL setup complete", 
                          details: "time=\(String(format: "%.3f", glSetupTime))s")

            // Capture version info asynchronously
            Task { [weak self] in
                guard let self, let client = self.mpvClient else { return }
                self.versionInfo = await client.getVersionInfoAsync()
            }

            let totalTime = Date().timeIntervalSince(startTime)
            let timeSinceInit = Date().timeIntervalSince(setupStartTime)
            
            LoggingService.shared.logMPV("MPV backend initialized", 
                                         details: "setup=\(String(format: "%.3f", totalTime))s, sinceInit=\(String(format: "%.3f", timeSinceInit))s, gl=\(String(format: "%.3f", glSetupTime))s")
            MPVLogging.log("setupMPVAsync: complete")
            
            isSetupComplete = true
        } catch {
            LoggingService.shared.logMPVError("Failed to initialize MPV", error: error)
            MPVLogging.warn("setupMPVAsync: FAILED", details: "\(error)")
        }
    }

    private func cleanup() {
        // Stop buffer stall detection
        stopBufferStallDetection()

        #if os(macOS)
        // Clear MPV client callbacks before destroying - these reference the render view
        // which will be deallocated
        mpvClient?.onRenderUpdate = nil
        mpvClient?.onVideoFrameReady = nil
        #endif

        // Remove player view from its superview to prevent orphaned views
        // covering new player views in the view hierarchy
        _playerView?.removeFromSuperview()

        mpvClient?.destroy()
        mpvClient = nil
        renderView = nil
        _playerView = nil
    }

    // MARK: - Playback Control

    func load(stream: Stream, audioStream: Stream?, autoplay: Bool, useEDL: Bool) async throws {
        // Wait for setup to complete before loading
        MPVLogging.log("MPVBackend.load: waiting for setup")
        try await waitForSetup()
        MPVLogging.log("MPVBackend.load: setup complete, proceeding with load")
        
        // Disable EDL for live streams - MPV's EDL doesn't handle live streams properly
        // (live streams have no fixed duration and infinite length, which breaks EDL demuxer)
        let actualUseEDL = useEDL && !stream.isLive
        if stream.isLive && useEDL {
            LoggingService.shared.debug("MPV: Disabling EDL for live stream (live streams not compatible with EDL)", category: .mpv)
        }
        
        LoggingService.shared.logMPV("MPV loading stream", details: "\(stream.qualityLabel) - \(stream.format)\n\(stream.url.absoluteString)\nEDL: \(actualUseEDL) (requested: \(useEDL), isLive: \(stream.isLive))\nStream info: videoCodec=\(stream.videoCodec ?? "nil"), audioCodec=\(stream.audioCodec ?? "nil")")
        if let audioStream {
            LoggingService.shared.logMPV("MPV loading separate audio track", details: "\(audioStream.audioLanguage ?? "default") - \(audioStream.format)\n\(audioStream.url.absoluteString)\nAudio codec: \(audioStream.audioCodec ?? "nil")")
        }

        // Cancel any previous loading operation by changing the ID
        let loadingID = UUID()
        currentLoadingID = loadingID
        
        // IMMEDIATELY mark as loading to protect against .stop events from previous stream
        // This must happen before any async work to prevent race conditions where .stop
        // events from the previous stream see isInitialLoading=false and report idle state
        isInitialLoading = true

        // Store for potential retries
        currentStream = stream
        currentAudioStream = audioStream
        pendingAutoplay = autoplay
        pendingUseEDL = actualUseEDL
        retryCount = 0

        // Reset retry state in UI
        delegate?.backend(self, didUpdateRetryState: 0, maxRetries: maxRetries, isRetrying: false, exhausted: false)

        // Try loading with retries
        try await loadWithRetry(stream: stream, audioStream: audioStream, autoplay: autoplay, useEDL: actualUseEDL, loadingID: loadingID)
    }

    private var pendingUseEDL: Bool = true

    private func loadWithRetry(stream: Stream, audioStream: Stream?, autoplay: Bool, useEDL: Bool, loadingID: UUID) async throws {
        // Check if this load operation was cancelled (a new load started)
        guard currentLoadingID == loadingID else {
            LoggingService.shared.debug("MPV load operation cancelled - newer load in progress", category: .mpv)
            throw CancellationError()
        }

        // Reset state (but keep videoWidth/videoHeight for smooth aspect ratio transition)
        isReady = false
        isInitialLoading = true
        isSeeking = false
        hasDisplayedVideo = false
        hasStartedPlayback = false
        hasReachedEOF = false
        pendingPlayAfterSeek = false
        // Note: pendingInitialSeek is NOT reset here - it's set by prepareForInitialSeek()
        // before load() is called, and cleared when seek() starts
        currentTime = 0
        duration = 0
        bufferedTime = 0
        // When loading with external audio (non-EDL mode), wait for PLAYBACK_RESTART after audio is added
        // With EDL, both streams load atomically so no waiting needed
        isWaitingForExternalAudio = audioStream != nil && !useEDL

        // Clear any subtitles from previous video
        currentCaption = nil
        mpvClient?.removeAllSubtitlesAsync()

        // Reset first-frame tracking for new content
        renderView?.resetFirstFrameTracking()

        // Pause MPV before loading new content to prevent audio from playing
        // before the thumbnail hides. This is critical when reusing the backend
        // for a new video - without this, MPV may output audio during buffering.
        mpvClient?.pause()

        // Clear the render view to black to hide any old frame from previous video
        renderView?.clearToBlack()

        // Load the stream
        do {
            try mpvClient?.loadFile(stream.url, audioURL: audioStream?.url, httpHeaders: stream.httpHeaders, useEDL: useEDL)
            
            // Give MPV a moment to process the loadfile command
            try await Task.sleep(for: .milliseconds(100))
            
            // Log diagnostics asynchronously (background priority) - don't block video loading
            // These are non-critical diagnostic logs that shouldn't impact UI responsiveness
            Task.detached(priority: .background) { [weak self] in
                guard let mpvClient = await self?.mpvClient else { return }
                let idleActive = await mpvClient.getFlagAsync("idle-active")
                let coreIdle = await mpvClient.getFlagAsync("core-idle")
                let seeking = await mpvClient.getFlagAsync("seeking")
                LoggingService.shared.debug(
                    "MPV: After loadfile - idle-active=\(idleActive?.description ?? "nil"), core-idle=\(coreIdle?.description ?? "nil"), seeking=\(seeking?.description ?? "nil")",
                    category: .mpv
                )
            }

            // Wait for file to be loaded
            try await waitForReady(loadingID: loadingID)

            // Check again after waiting
            guard currentLoadingID == loadingID else {
                LoggingService.shared.debug("MPV load operation cancelled after ready - newer load in progress", category: .mpv)
                throw CancellationError()
            }

            // Reset retry state on success
            isInitialLoading = false
            resetRetryState()

            if autoplay {
                play()
            }

            LoggingService.shared.logMPV("MPV stream loaded successfully")
        } catch is CancellationError {
            // Re-throw cancellation errors without retry
            // Only reset isInitialLoading if we're still the active load operation
            // A newer load may have already set isInitialLoading=true
            if currentLoadingID == loadingID {
                isInitialLoading = false
            }
            throw CancellationError()
        } catch {
            // Check if cancelled before retrying
            guard currentLoadingID == loadingID else {
                LoggingService.shared.debug("MPV load operation cancelled - newer load in progress", category: .mpv)
                // Don't reset isInitialLoading - a newer load owns it now
                throw CancellationError()
            }

            // Retry if we haven't exhausted attempts
            if retryCount < maxRetries {
                let delay = retryDelays[min(retryCount, retryDelays.count - 1)]
                retryCount += 1

                // Notify delegate that retry is starting
                delegate?.backend(self, didUpdateRetryState: retryCount, maxRetries: maxRetries, isRetrying: true, exhausted: false)

                let nextTimeout = loadTimeouts[min(retryCount, loadTimeouts.count - 1)]
                LoggingService.shared.warning("MPV stream load retry", category: .mpv, details: "Waiting \(Int(delay))s before attempt \(retryCount + 1)/\(maxRetries + 1) (timeout: \(Int(nextTimeout))s)")

                // Wait before retrying
                try await Task.sleep(for: .seconds(delay))

                // Check if cancelled after delay
                guard currentLoadingID == loadingID, !Task.isCancelled else {
                    LoggingService.shared.debug("MPV load operation cancelled during retry delay", category: .mpv)
                    // Don't reset isInitialLoading - a newer load owns it now
                    throw CancellationError()
                }
                try await loadWithRetry(stream: stream, audioStream: audioStream, autoplay: autoplay, useEDL: useEDL, loadingID: loadingID)
            } else {
                // All retries exhausted
                isInitialLoading = false
                LoggingService.shared.logMPVError("MPV stream load failed after \(retryDelays.count + 1) attempts")

                // Notify delegate that all retries exhausted
                delegate?.backend(self, didUpdateRetryState: maxRetries, maxRetries: maxRetries, isRetrying: false, exhausted: true)

                resetRetryState()
                throw error
            }
        }
    }

    /// Maximum number of retries
    private var maxRetries: Int {
        retryDelays.count
    }

    /// Timeout for current attempt
    private var currentLoadTimeout: TimeInterval {
        loadTimeouts[min(retryCount, loadTimeouts.count - 1)]
    }

    private func resetRetryState() {
        retryCount = 0
        currentStream = nil
        currentAudioStream = nil
        pendingAutoplay = false
        delegate?.backend(self, didUpdateRetryState: 0, maxRetries: maxRetries, isRetrying: false, exhausted: false)
    }

    func play() {
        guard isReady else {
            // Not ready yet - set pending flag to auto-play when ready
            LoggingService.shared.debug("MPV: play() called while not ready, setting pendingPlayAfterSeek", category: .mpv)
            pendingPlayAfterSeek = true
            return
        }

        LoggingService.shared.debug("MPV: play() called, isReady=\(isReady), cacheTime=\(demuxerCacheTime)s", category: .mpv)
        mpvClient?.play()
        isPlaying = true
        delegate?.backend(self, didChangeState: .playing)
    }

    /// Wait for sufficient buffer before starting playback.
    /// This prevents the initial pause/stutter that occurs when MPV starts playing
    /// before enough content is buffered.
    /// - Parameters:
    ///   - minimumBuffer: Minimum buffer time required before playback starts (default 3.0 seconds)
    ///   - timeout: Maximum time to wait for buffer (default 5 seconds)
    /// - Returns: The buffer time when wait completed
    func waitForBuffer(minimumBuffer: Double = 3.0, timeout: TimeInterval = 5.0) async -> Double {
        let startTime = Date()
        var lastLogTime = startTime

        // First, wait for any pending seek to complete
        // After a seek, the buffer at the new position needs to refill
        while isSeeking {
            if Date().timeIntervalSince(startTime) >= timeout {
                LoggingService.shared.debug("MPV: Buffer wait timeout while waiting for seek", category: .mpv)
                return 0
            }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        LoggingService.shared.debug("MPV: Seek complete, now waiting for buffer to fill", category: .mpv)

        // After seek completes, give the demuxer a moment to start filling the buffer
        // at the new position. Without this, we might read stale cache values.
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Fast-path: If cache is already satisfied, return immediately
        // This handles fully buffered content (short videos, previously buffered, etc.)
        let initialBufferingState = cacheBufferingState
        let initialPausedForCache = pausedForCache
        if initialBufferingState >= 100 && !initialPausedForCache {
            return demuxerCacheTime
        }

        // Capture the initial cache time as a baseline
        // demuxer-cache-time returns total cached content from file start, not from seek position
        // So when seeking to 100s, cache might already be 100s even though buffer at that position is empty
        let initialCacheTime = demuxerCacheTime
        let targetCacheTime = initialCacheTime + minimumBuffer

        // Now wait for sufficient buffer at the current position
        // We check multiple conditions:
        // 1. demuxer-cache-time: seconds of video buffered (relative to baseline)
        // 2. cache-buffering-state: 0-100% of how full the cache is until MPV will unpause
        // 3. paused-for-cache: whether MPV would pause due to insufficient cache
        var lastCacheTime: Double = initialCacheTime
        var noProgressCount = 0

        while true {
            // Use cached values (updated via property observation) to avoid sync fetch on main thread
            let cacheTime = demuxerCacheTime
            let bufferingState = cacheBufferingState
            let isPausedForCache = pausedForCache

            // Calculate progress as percentage towards our minimum buffer target
            // Use the delta from initial cache time to show meaningful progress after seeks
            let bufferedSinceStart = max(0, cacheTime - initialCacheTime)
            let bufferProgress = min(Int((bufferedSinceStart / minimumBuffer) * 100), 99)
            delegate?.backend(self, didUpdateBufferProgress: bufferProgress)

            // Log progress every 0.5 seconds
            if Date().timeIntervalSince(lastLogTime) >= 0.5 {
                LoggingService.shared.debug("MPV: Waiting for buffer... cacheTime=\(String(format: "%.2f", cacheTime))s (delta=\(String(format: "%.2f", bufferedSinceStart))s), bufferingState=\(bufferingState)%, pausedForCache=\(isPausedForCache), target=\(minimumBuffer)s, progress=\(bufferProgress)%", category: .mpv)
                lastLogTime = Date()
            }

            // Primary condition: We have enough cached time relative to where we started
            let hasEnoughTime = cacheTime >= targetCacheTime

            if hasEnoughTime {
                LoggingService.shared.debug("MPV: Buffer ready, cacheTime=\(String(format: "%.2f", cacheTime))s (delta=\(String(format: "%.2f", bufferedSinceStart))s), bufferingState=\(bufferingState)%, reason=enough time", category: .mpv)
                return cacheTime
            }

            // Track if buffer isn't growing (video fully downloaded or other issue)
            if cacheTime <= lastCacheTime {
                noProgressCount += 1
            } else {
                noProgressCount = 0
                lastCacheTime = cacheTime
            }

            // Fallback: If MPV's cache is satisfied AND buffer isn't growing for 0.5s (10 checks),
            // the video is likely short/fully buffered, so proceed
            let cacheIsSatisfied = bufferingState >= 100 && !isPausedForCache
            if cacheIsSatisfied && noProgressCount >= 10 {
                LoggingService.shared.debug("MPV: Buffer ready, cacheTime=\(String(format: "%.2f", cacheTime))s (delta=\(String(format: "%.2f", bufferedSinceStart))s), bufferingState=\(bufferingState)%, reason=cache satisfied (no progress)", category: .mpv)
                return cacheTime
            }

            // Check timeout
            if Date().timeIntervalSince(startTime) >= timeout {
                LoggingService.shared.debug("MPV: Buffer wait timeout, proceeding with cacheTime=\(String(format: "%.2f", cacheTime))s, bufferingState=\(bufferingState)%", category: .mpv)
                return cacheTime
            }

            // Wait a bit before checking again
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
    }

    func pause() {
        mpvClient?.pause()
        isPlaying = false
        delegate?.backend(self, didChangeState: .paused)
    }

    func stop() {
        #if os(iOS) || os(macOS)
        // Stop PiP if active before stopping playback
        if pipBridge?.isPiPActive == true {
            stopPiP()
        }
        // Flush PiP buffer to clear stale frames when reusing backend
        pipBridge?.flushBuffer()
        // Immediately reset PiP-related state (don't wait for async callbacks)
        // This ensures the next video can start with clean state
        _playerView?.isPiPActive = false
        _playerView?.captureFramesForPiP = false
        pipPlayerState?.pipState = .inactive
        // Note: Don't clear onFrameReady/onFirstFrameRendered callbacks - they're
        // set once in setupMPV() and needed for subsequent video loads when reusing backend
        #endif

        #if os(macOS)
        // On macOS, also clean up PiP bridge callbacks to prevent crashes
        // during window close
        pipBridge?.onPiPStatusChanged = nil
        pipBridge?.onPiPWillStart = nil
        pipBridge?.onPiPWillStop = nil
        pipBridge?.onPiPRenderSizeChanged = nil

        // NOTE: Do NOT clear mpvClient?.onRenderUpdate here!
        // The onRenderUpdate callback is set once during setup and needs to persist
        // across video changes. Clearing it here would break rendering for subsequent
        // videos since setup() is only called once per backend lifetime.
        // The callback will be properly cleared in cleanup() when the backend is destroyed.
        #endif

        // Stop buffer stall detection
        stopBufferStallDetection()

        mpvClient?.stop()
        isPlaying = false
        isReady = false
        hasReachedEOF = false
        pendingInitialSeek = false
        currentTime = 0
        duration = 0
        bufferedTime = 0
        currentStream = nil
        delegate?.backend(self, didChangeState: .idle)
    }

    func prepareForInitialSeek() {
        // Signal that an initial seek will be performed after load completes.
        // This defers backendDidBecomeReady until the seek completes.
        pendingInitialSeek = true
        LoggingService.shared.debug("MPV: Preparing for initial seek", category: .mpv)
    }

    func seek(to time: TimeInterval, showLoading: Bool = false) async {
        // Clear pending initial seek flag - we're now doing the seek
        pendingInitialSeek = false

        // Clear EOF state when seeking (e.g., restart from beginning)
        hasReachedEOF = false

        // For initial resume seeks (before playback has really started),
        // or when explicitly requested (e.g., SponsorBlock intro skip),
        // reset ready state so we keep showing loading until video at new position is visible
        let shouldShowLoading = !hasStartedPlayback || showLoading

        if shouldShowLoading {
            LoggingService.shared.debug("MPV: Seek with loading state - resetting for new position", category: .mpv)
            hasDisplayedVideo = false
            hasStartedPlayback = false
            renderView?.resetFirstFrameTracking()

            // Pause MPV during seek to prevent brief playback at wrong position
            if isPlaying {
                mpvClient?.pause()
                pendingPlayAfterSeek = true
            }

            if isReady {
                isReady = false
                // Tell UI to go back to loading state
                delegate?.backend(self, didChangeState: .loading)
            }
        }

        // Set seeking immediately - don't wait for MPV's property update
        isSeeking = true

        // Use async seek to avoid blocking the main thread
        // Seek completion is tracked via MPV's "seeking" property observation
        mpvClient?.seekAsync(to: time)
        currentTime = time
        delegate?.backend(self, didUpdateTime: time)
    }

    /// Tracks if we need to resume playback after initial seek completes
    private var pendingPlayAfterSeek = false

    /// Tracks if MPV is currently seeking
    private var isSeeking = false

    /// Tracks if we've actually displayed video (first frame rendered)
    private var hasDisplayedVideo = false

    /// Tracks if real playback has started (user has seen video playing at intended position)
    /// This distinguishes initial resume seeks from user-initiated seeks during playback
    private var hasStartedPlayback = false

    /// Tracks if an initial seek is pending after load completes
    /// When true, handleFirstFrameRendered won't call backendDidBecomeReady until seek completes
    private var pendingInitialSeek = false


    // MARK: - Backend Switching

    func captureState() -> BackendState {
        BackendState(
            currentTime: currentTime,
            duration: duration,
            rate: _rate,
            volume: _volume,
            isMuted: _isMuted,
            isPlaying: isPlaying
        )
    }

    func restore(state: BackendState) async {
        _rate = state.rate
        _volume = state.volume
        _isMuted = state.isMuted

        // Apply to MPV
        mpvClient?.setProperty("speed", Double(state.rate))
        mpvClient?.setProperty("volume", Double(state.volume * 100))
        mpvClient?.setProperty("mute", state.isMuted)

        if state.currentTime > 0 {
            await seek(to: state.currentTime)
        }

        if state.isPlaying {
            play()
        }
    }

    func prepareForHandoff() {
        mpvClient?.pause()
        isPlaying = false
    }

    // MARK: - Subtitles

    /// Load and display a caption/subtitle track.
    /// - Parameter caption: The caption to load, or nil to disable subtitles
    func loadCaption(_ caption: Caption?) {
        // Remove any existing subtitles first (async to not block UI)
        mpvClient?.removeAllSubtitlesAsync()

        guard let caption else {
            // Disable subtitles
            mpvClient?.disableSubtitles()
            currentCaption = nil
            LoggingService.shared.debug("MPV: Subtitles disabled", category: .mpv)
            return
        }

        // Load the new subtitle asynchronously to avoid blocking UI during download
        LoggingService.shared.debug("MPV: Loading subtitle: \(caption.displayName)", category: .mpv)
        mpvClient?.addSubtitleAsync(caption.url, select: true)
        currentCaption = caption
    }

    /// Get the currently loaded caption.
    func getCurrentCaption() -> Caption? {
        currentCaption
    }

    /// Update subtitle appearance settings on the active MPV instance.
    /// Call this after changing subtitle settings to apply them immediately without restarting playback.
    func updateSubtitleSettings() {
        mpvClient?.updateSubtitleSettings()
    }

    /// Get the actual video track dimensions from MPV.
    /// Returns (width, height) or nil if not available.
    func getVideoSize() -> (width: Int, height: Int)? {
        // Use cached values (updated via property observation) to avoid sync fetch
        guard videoWidth > 0, videoHeight > 0 else {
            return nil
        }
        return (videoWidth, videoHeight)
    }

    /// Get debug statistics from MPV for the debug overlay.
    /// Uses batch fetch to minimize lock contention (single sync block instead of ~25 separate calls).
    func getDebugStats() -> MPVDebugStats {
        var stats = MPVDebugStats()

        // Fetch all properties in a single sync block
        guard let props = mpvClient?.getDebugProperties() else {
            return stats
        }

        // Video info
        stats.videoCodec = props.videoCodec
        stats.hwdecCurrent = props.hwdecCurrent
        stats.width = props.width
        stats.height = props.height
        stats.fps = props.containerFps
        stats.estimatedVfFps = props.estimatedVfFps

        // Audio info
        stats.audioCodec = props.audioCodecName
        stats.audioSampleRate = props.audioSampleRate
        stats.audioChannels = props.audioChannels

        // Playback stats
        stats.droppedFrameCount = props.frameDropCount
        stats.mistimedFrameCount = props.mistimedFrameCount
        stats.delayedFrameCount = props.voDelayedFrameCount
        stats.avSync = props.avsync
        stats.estimatedFrameNumber = props.estimatedFrameNumber

        // Cache/Network
        if let cacheState = props.cacheState {
            stats.cacheDuration = cacheState.cacheDuration
            stats.cacheBytes = cacheState.totalBytes
            stats.networkSpeed = cacheState.inputRate
        }
        stats.demuxerCacheDuration = props.demuxerCacheDuration

        // Container
        stats.fileFormat = props.fileFormat
        stats.containerFps = props.containerFps

        // Video Sync stats (for tvOS frame timing diagnostics)
        #if os(tvOS)
        stats.videoSync = props.videoSync
        stats.displayFps = props.displayFps
        stats.vsyncJitter = props.vsyncJitter
        stats.videoSpeedCorrection = props.videoSpeedCorrection
        stats.audioSpeedCorrection = props.audioSpeedCorrection
        stats.framedrop = props.framedrop
        stats.displayLinkFps = renderView?.displayLinkTargetFPS
        #endif

        return stats
    }

    // MARK: - Background Playback

    func handleScenePhase(_ phase: ScenePhase, backgroundEnabled: Bool, isPiPActive: Bool) {
        #if os(iOS)
        let pipActive = self.isPiPActive || isPiPActive
        #else
        let pipActive = isPiPActive
        #endif

        MPVLogging.logAppLifecycle("handleScenePhase(\(phase))",
            isPiPActive: pipActive, isRendering: nil)

        guard backgroundEnabled, !pipActive else {
            MPVLogging.log("handleScenePhase: skipping (bgEnabled:\(backgroundEnabled) pip:\(pipActive))")
            return
        }

        switch phase {
        case .background:
            // Just pause rendering - don't touch video track or output properties
            // This preserves the demuxer cache and avoids rebuffering on resume
            // Same approach as handlePlayerSheetVisibility
            LoggingService.shared.debug("MPV: Pausing rendering for background", category: .mpv)
            MPVLogging.log("handleScenePhase: pausing rendering for background")
            #if os(macOS)
            _playerView?.pauseRendering()
            #elseif targetEnvironment(simulator)
            (playerView as? MPVSoftwareRenderView)?.pauseRendering()
            #else
            (playerView as? MPVRenderView)?.pauseRendering()
            #endif

        case .active:
            // Resume rendering
            LoggingService.shared.debug("MPV: Resuming rendering for foreground", category: .mpv)
            MPVLogging.log("handleScenePhase: resuming rendering for foreground")
            #if os(macOS)
            _playerView?.resumeRendering()
            #elseif targetEnvironment(simulator)
            (playerView as? MPVSoftwareRenderView)?.resumeRendering()
            #else
            (playerView as? MPVRenderView)?.resumeRendering()
            #endif

        default:
            break
        }
    }

    /// Handles player sheet visibility changes for background audio playback.
    /// - Parameter isVisible: true when sheet appears, false when it disappears
    ///
    /// Note: We only pause/resume rendering, NOT disable the video track.
    /// Disabling the video track (`vid=no`) stops video decoding while audio continues,
    /// causing severe A/V desync when video is re-enabled. Instead, we keep decoding
    /// running but pause the display link to save GPU while maintaining sync.
    func handlePlayerSheetVisibility(isVisible: Bool) {
        #if os(iOS)
        let hasFirstFrame = hasDisplayedVideo
        let currentlyPlaying = isPlaying
        let ready = isReady
        LoggingService.shared.debug("MPV: handlePlayerSheetVisibility(isVisible=\(isVisible)) - hasDisplayedVideo=\(hasFirstFrame), isPlaying=\(currentlyPlaying), isReady=\(ready), _playerView=\(_playerView != nil)", category: .mpv)
        MPVLogging.log("handlePlayerSheetVisibility(isVisible:\(isVisible))",
            details: "hasFirstFrame:\(hasFirstFrame) playing:\(currentlyPlaying) ready:\(ready)")

        if isVisible {
            LoggingService.shared.debug("MPV: Resuming rendering for sheet display", category: .mpv)
            MPVLogging.log("handlePlayerSheetVisibility: resuming rendering")
            _playerView?.resumeRendering()
        } else {
            LoggingService.shared.debug("MPV: Pausing rendering - sheet dismissed", category: .mpv)
            MPVLogging.log("handlePlayerSheetVisibility: pausing rendering")
            _playerView?.pauseRendering()
        }
        #endif
    }

    // MARK: - Picture-in-Picture (iOS)

    #if os(iOS)
    /// Tracks whether PiP has been set up
    private var isPiPSetUp = false

    /// Reference to the player state for updating isPiPPossible
    private weak var pipPlayerState: PlayerState?

    /// Reference to the container view for updating PiP layer frame after layout
    private weak var pipContainerView: UIView?

    /// Set up PiP if not already set up.
    /// Called from the representable when the view is updated.
    func setupPiPIfNeeded(in containerView: UIView, playerState: PlayerState?) {
        // Always store playerState so we have it when onDidMoveToWindow fires
        pipPlayerState = playerState

        // Only proceed with actual setup if not already done and view is in window
        guard !isPiPSetUp, containerView.window != nil else { return }

        // Store container reference for updating layer frame after layout
        pipContainerView = containerView

        setupPiP(in: containerView)
        isPiPSetUp = true

        // Update player state after a short delay to let PiP controller initialize
        // and container to be laid out with proper bounds
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            // Update sampleBufferLayer frame now that container has been laid out
            if let containerView = self?.pipContainerView, containerView.bounds.size != .zero {
                self?.pipBridge?.updateLayerFrame(containerView.bounds)
            }
            playerState?.isPiPPossible = self?.isPiPPossible ?? false
        }
    }

    /// Set up PiP with the given container view.
    /// - Parameters:
    ///   - containerView: The view to embed the PiP layer in
    func setupPiP(in containerView: UIView) {
        // Create PiP bridge if needed
        if pipBridge == nil {
            pipBridge = MPVPiPBridge()
        }

        guard let pipBridge else { return }

        // Set up the bridge with this backend and the container
        pipBridge.setup(backend: self, in: containerView)

        // Use the restore callback set by PlayerService
        pipBridge.onRestoreUserInterface = { [weak self] in
            await self?.onRestoreFromPiP?()
        }

        // Update render view's PiP status to control main view rendering
        pipBridge.onPiPStatusChanged = { [weak self] isActive in
            self?._playerView?.isPiPActive = isActive
            // Also update player state
            self?.pipPlayerState?.pipState = isActive ? .active : .inactive
            if isActive {
                // Notify that PiP started (to collapse player sheet)
                self?.onPiPDidStart?()
            } else {
                // Disable frame capture when PiP stops (after animation completes)
                self?._playerView?.captureFramesForPiP = false
            }
        }

        // Clear main view to black immediately when PiP starts animating
        pipBridge.onPiPWillStart = { [weak self] in
            // Enable frame capture - this handles system-triggered PiP (when user minimizes app)
            // where captureFramesForPiP wasn't set beforehand
            self?._playerView?.captureFramesForPiP = true
            // Stop presenting to main view immediately
            self?._playerView?.isPiPActive = true
            // Clear to black
            self?._playerView?.clearMainViewForPiP()
        }

        // Note: Main view rendering resumes in onPiPStatusChanged(false) after animation completes.
        // This allows the system "playing in PiP" placeholder to show during close animation.
        pipBridge.onPiPWillStop = { [weak self] in
            // Keep isPiPActive = true so main view shows placeholder during close animation
            _ = self  // Silence unused warning
        }

        // Connect frame capture from render view to PiP bridge
        _playerView?.onFrameReady = { [weak self] pixelBuffer, presentationTime in
            self?.enqueueFrameForPiP(pixelBuffer, presentationTime: presentationTime)
        }

        LoggingService.shared.debug("MPV: PiP setup complete", category: .mpv)
    }

    /// Start Picture-in-Picture.
    func startPiP() {
        guard pipBridge != nil else {
            LoggingService.shared.warning("MPV: Cannot start PiP - not set up", category: .mpv)
            return
        }

        startPiPInternal()
    }

    /// Internal method to actually start PiP after any fullscreen handling
    private func startPiPInternal() {
        // Enable frame capture for PiP - start capturing BEFORE requesting PiP
        // so the sample buffer layer has content
        _playerView?.captureFramesForPiP = true

        // Wait a moment for frames to be captured, then start PiP
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.pipBridge?.startPiP()
        }
    }

    /// Stop Picture-in-Picture.
    func stopPiP() {
        pipBridge?.stopPiP()
        // Frame capture is disabled in onPiPStatusChanged callback after animation completes
    }

    /// Toggle Picture-in-Picture.
    func togglePiP() {
        if isPiPActive {
            stopPiP()
        } else {
            startPiP()
        }
    }

    /// Called by render view when a frame is ready for PiP display.
    func enqueueFrameForPiP(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard let pipBridge else { return }

        // Update playback state for PiP controls
        pipBridge.updatePlaybackState(
            duration: duration,
            currentTime: currentTime,
            isPaused: !isPlaying
        )

        pipBridge.enqueueFrame(pixelBuffer, presentationTime: presentationTime)
    }

    /// Clean up PiP resources.
    func cleanupPiP() {
        _playerView?.captureFramesForPiP = false
        _playerView?.onFrameReady = nil
        pipBridge?.cleanup()
        pipBridge = nil
        isPiPSetUp = false
    }

    /// Move the PiP layer to a new container view.
    /// Call this before starting PiP from fullscreen to ensure the layer
    /// is in the main window's view hierarchy.
    func movePiPLayer(to containerView: UIView) {
        pipBridge?.moveLayer(to: containerView)
    }

    #elseif os(macOS)

    // MARK: - Picture-in-Picture (macOS)

    /// Set up PiP if not already set up.
    /// Called from the representable when the view is updated.
    func setupPiPIfNeeded(in containerView: NSView, playerState: PlayerState?) {
        // Always store playerState so we have it for later
        pipPlayerState = playerState

        // Only proceed with actual setup if not already done and view is in window
        guard !isPiPSetUp, containerView.window != nil else {
            // If already set up but playerState changed, update isPiPPossible
            if isPiPSetUp, let playerState {
                playerState.isPiPPossible = isPiPPossible
            }
            return
        }

        // Store container reference for updating layer frame after layout
        pipContainerView = containerView

        setupPiP(in: containerView)
        isPiPSetUp = true

        // Update sampleBufferLayer frame after a short delay now that container has been laid out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            if let containerView = self?.pipContainerView, containerView.bounds.size != .zero {
                // On macOS, use the method that calculates frame relative to window's content view
                self?.pipBridge?.updateLayerFrame(for: containerView)
            }
        }
        // Note: playerState.isPiPPossible is updated via KVO observation in pipBridge.onPiPPossibleChanged
    }

    /// Set up PiP with the given container view.
    func setupPiP(in containerView: NSView) {
        // Create PiP bridge if needed
        if pipBridge == nil {
            pipBridge = MPVPiPBridge()
        }

        guard let pipBridge else { return }

        // Set up the bridge with this backend and the container
        pipBridge.setup(backend: self, in: containerView)

        // Use the restore callback set by PlayerService
        pipBridge.onRestoreUserInterface = { [weak self] in
            await self?.onRestoreFromPiP?()
        }

        // Update render view's PiP status to control main view rendering
        pipBridge.onPiPStatusChanged = { [weak self] isActive in
            LoggingService.shared.debug("MPVBackend (macOS): onPiPStatusChanged isActive=\(isActive), onPiPDidStart=\(self?.onPiPDidStart != nil ? "set" : "nil")", category: .mpv)
            self?._playerView?.isPiPActive = isActive
            self?.pipPlayerState?.pipState = isActive ? .active : .inactive
            if isActive {
                self?.onPiPDidStart?()
            } else {
                self?._playerView?.captureFramesForPiP = false
            }
        }

        // Clear main view to black immediately when PiP starts animating
        pipBridge.onPiPWillStart = { [weak self] in
            self?._playerView?.captureFramesForPiP = true
            self?._playerView?.isPiPActive = true
            self?._playerView?.clearMainViewForPiP()
        }

        pipBridge.onPiPWillStop = { [weak self] in
            _ = self
        }

        // Clean up hidden window when PiP is closed (not restored)
        pipBridge.onPiPDidStopWithoutRestore = { [weak self] in
            self?.onPiPDidStopWithoutRestore?()
        }

        // Connect frame capture from render view to PiP bridge
        _playerView?.onFrameReady = { [weak self] pixelBuffer, presentationTime in
            self?.enqueueFrameForPiP(pixelBuffer, presentationTime: presentationTime)
        }

        // Update playerState when isPiPPossible changes (via KVO)
        pipBridge.onPiPPossibleChanged = { [weak self] isPossible in
            self?.pipPlayerState?.isPiPPossible = isPossible
        }

        // Update render view's PiP capture size when PiP window size changes
        pipBridge.onPiPRenderSizeChanged = { [weak self] size in
            self?._playerView?.updatePiPTargetSize(size)
        }

        // Manually notify current state now that callbacks are set up
        pipBridge.notifyPiPPossibleState()
    }

    /// Start Picture-in-Picture.
    func startPiP() {
        guard pipBridge != nil else {
            LoggingService.shared.warning("MPV (macOS): Cannot start PiP - not set up", category: .mpv)
            return
        }

        // Enable frame capture for PiP - start capturing BEFORE requesting PiP
        _playerView?.captureFramesForPiP = true

        // Wait a moment for frames to be captured, then start PiP
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.pipBridge?.startPiP()
        }
    }

    /// Stop Picture-in-Picture.
    func stopPiP() {
        pipBridge?.stopPiP()
    }

    /// Toggle Picture-in-Picture.
    func togglePiP() {
        if isPiPActive {
            stopPiP()
        } else {
            startPiP()
        }
    }

    /// Called by render view when a frame is ready for PiP display.
    func enqueueFrameForPiP(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard let pipBridge else { return }

        pipBridge.updatePlaybackState(
            duration: duration,
            currentTime: currentTime,
            isPaused: !isPlaying
        )

        pipBridge.enqueueFrame(pixelBuffer, presentationTime: presentationTime)
    }

    /// Clean up PiP resources.
    func cleanupPiP() {
        _playerView?.captureFramesForPiP = false
        _playerView?.onFrameReady = nil
        pipBridge?.cleanup()
        pipBridge = nil
        isPiPSetUp = false
    }

    /// Move the PiP layer to a new container view.
    func movePiPLayer(to containerView: NSView) {
        pipBridge?.moveLayer(to: containerView)
    }
    #endif

    // MARK: - Private Methods

    /// Called when the render view has rendered its first frame.
    /// This is used to track that we've actually displayed video content.
    private func handleFirstFrameRendered() {
        // Verify this callback belongs to a current load operation
        // (defends against stale callbacks from a previous video)
        guard currentLoadingID != nil else {
            LoggingService.shared.debug("MPV: Ignoring stale first frame callback (no active load)", category: .mpv)
            return
        }

        hasDisplayedVideo = true
        LoggingService.shared.debug("MPV: First frame rendered, hasDisplayedVideo = true, pendingInitialSeek = \(pendingInitialSeek), cacheTime = \(demuxerCacheTime)s", category: .mpv)

        // If we're waiting to mark ready after a resume seek, do it now
        // Don't mark ready if an initial seek is pending - wait until seek completes
        if !isReady && !isSeeking && !pendingInitialSeek {
            isReady = true
            hasStartedPlayback = true

            // Resume playback if we paused for initial seek
            if pendingPlayAfterSeek {
                pendingPlayAfterSeek = false
                mpvClient?.play()
                LoggingService.shared.debug("MPV: First frame rendered, resuming playback after initial seek", category: .mpv)
            }

            // Notify UI that we're ready to show video
            delegate?.backendDidBecomeReady(self)
            delegate?.backend(self, didChangeState: isPlaying ? .playing : .ready)
        }
    }

    private func waitForReady(loadingID: UUID) async throws {
        let start = Date()
        let timeout = currentLoadTimeout

        LoggingService.shared.debug("MPV: Waiting for stream ready (timeout: \(Int(timeout))s, attempt \(retryCount + 1)/\(maxRetries + 1))", category: .mpv)

        // Wait for video to be ready
        while !isReady {
            // Check if this load was cancelled
            guard currentLoadingID == loadingID else {
                throw CancellationError()
            }

            if Date().timeIntervalSince(start) > timeout {
                throw BackendError.loadFailed("Timeout waiting for MPV to load stream (\(Int(timeout))s)")
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        // If we have an external audio track, wait for PLAYBACK_RESTART after audio is added
        if isWaitingForExternalAudio {
            LoggingService.shared.debug("MPV: Waiting for external audio track to load", category: .mpv)
            while isWaitingForExternalAudio {
                guard currentLoadingID == loadingID else {
                    throw CancellationError()
                }

                if Date().timeIntervalSince(start) > timeout {
                    throw BackendError.loadFailed("Timeout waiting for audio track (\(Int(timeout))s)")
                }

                try await Task.sleep(for: .milliseconds(100))
            }
            LoggingService.shared.debug("MPV: External audio track loaded", category: .mpv)
        }

        delegate?.backendDidBecomeReady(self)
        delegate?.backend(self, didChangeState: .ready)
    }
}

// MARK: - MPVClientDelegate

extension MPVBackend: MPVClientDelegate {
    nonisolated func mpvClient(_ client: MPVClient, didUpdateProperty property: String, value: Any?) {
        Task { @MainActor [weak self] in
            self?.handlePropertyChange(property: property, value: value)
        }
    }

    nonisolated func mpvClient(_ client: MPVClient, didReceiveEvent event: mpv_event_id) {
        Task { @MainActor [weak self] in
            self?.handleEvent(event)
        }
    }

    nonisolated func mpvClient(_ client: MPVClient, didUpdateCacheState cacheState: MPVCacheState) {
        // Cache state is used for buffer display on seek bar - no action needed here
    }

    nonisolated func mpvClientDidEndFile(_ client: MPVClient, reason: MPVEndFileReason) {
        Task { @MainActor [weak self] in
            self?.handleEndFile(reason: reason)
        }
    }

    // MARK: - Event Handlers

    private func handlePropertyChange(property: String, value: Any?) {
        switch property {
        case "time-pos":
            if let time = value as? Double, time >= 0 {
                currentTime = time
                renderView?.updateTimePosition(time)
                delegate?.backend(self, didUpdateTime: time)
                // Ready state is now handled by handleFirstFrameRendered()
            }

        case "duration":
            if let dur = value as? Double, dur > 0 {
                duration = dur
                delegate?.backend(self, didUpdateDuration: dur)

                // Audio-only streams may become ready once duration is known
                checkAndMarkReadyIfAudioOnlyDetected()
            }

        case "pause":
            if let paused = value as? Bool {
                LoggingService.shared.debug("MPV: pause = \(paused), isReady = \(isReady), hasReachedEOF = \(hasReachedEOF)", category: .mpv)
                isPlaying = !paused
                // Only send state changes after we're ready (have actual video)
                // This prevents premature transition from loading to playing
                // Don't override ended state when MPV pauses at EOF (keep-open=yes)
                if isReady && !hasReachedEOF {
                    delegate?.backend(self, didChangeState: paused ? .paused : .playing)
                }
            }

        case "demuxer-cache-time":
            if let cached = value as? Double, cached >= 0 {
                demuxerCacheTime = cached
                bufferedTime = currentTime + cached
                delegate?.backend(self, didUpdateBufferedTime: bufferedTime)
            }

        case "speed":
            if let speed = value as? Double {
                _rate = Float(speed)
            }

        case "volume":
            if let vol = value as? Double {
                _volume = Float(vol / 100)
            }

        case "mute":
            if let muted = value as? Bool {
                _isMuted = muted
            }

        case "core-idle":
            // core-idle indicates MPV is processing, but doesn't mean frames are ready
            break

        case "eof-reached":
            // With keep-open=yes, MPV sends eof-reached=true instead of end-file event
            if let eofReached = value as? Bool {
                hasReachedEOF = eofReached
                if eofReached {
                    LoggingService.shared.debug("MPV: EOF reached", category: .mpv)
                    isPlaying = false
                    delegate?.backend(self, didChangeState: .ended)
                    delegate?.backendDidFinishPlaying(self)
                }
            }

        case "seeking":
            if let seeking = value as? Bool {
                isSeeking = seeking
                LoggingService.shared.debug("MPV: seeking = \(seeking), hasDisplayedVideo = \(hasDisplayedVideo), isReady = \(isReady)", category: .mpv)

                // When seeking completes, check if we can mark ready
                if !seeking {
                    // Try to mark ready based on video size (fallback for render callback)
                    checkAndMarkReadyIfVideoAvailable()

                    // If we already displayed a frame before seek started, we can mark ready now
                    // This handles the case where handleFirstFrameRendered was deferred due to pendingInitialSeek
                    if hasDisplayedVideo && !isReady {
                        LoggingService.shared.debug("MPV: Seek completed with displayed video, marking ready", category: .mpv)
                        isReady = true
                        hasStartedPlayback = true

                        // Resume playback if we paused for initial seek
                        if pendingPlayAfterSeek {
                            pendingPlayAfterSeek = false
                            mpvClient?.play()
                        }

                        delegate?.backendDidBecomeReady(self)
                        delegate?.backend(self, didChangeState: isPlaying ? .playing : .ready)
                    }
                }
            }

        case "width":
            if let width = value as? Int64, width > 0 {
                videoWidth = Int(width)
                notifyVideoSizeIfReady()
            }

        case "height":
            if let height = value as? Int64, height > 0 {
                videoHeight = Int(height)
                notifyVideoSizeIfReady()
            }

        case "container-fps":
            if let fps = value as? Double, fps > 0 {
                containerFps = fps
                updateRenderViewFPS()
            }

        case "paused-for-cache":
            if let isPausedForCache = value as? Bool {
                pausedForCache = isPausedForCache
                // Use cached values to avoid sync fetch on main thread
                LoggingService.shared.debug("MPV: paused-for-cache = \(isPausedForCache), cache-time = \(demuxerCacheTime)s", category: .mpv)

                // Check for buffer stall condition
                if isPausedForCache && cacheBufferingState == 0 && !isInitialLoading {
                    startBufferStallDetection()
                } else {
                    stopBufferStallDetection()
                }
            }

        case "cache-buffering-state":
            if let state = value as? Int64 {
                cacheBufferingState = Int(state)
                LoggingService.shared.debug("MPV: cache-buffering-state = \(state)%", category: .mpv)
                delegate?.backend(self, didUpdateBufferProgress: Int(state))

                // If buffer is no longer at 0%, cancel stall detection
                if state > 0 {
                    stopBufferStallDetection()
                }
            }

        case "video-codec":
            if let codec = value as? String {
                videoCodec = codec
            }

        case "hwdec-current":
            if let hwdec = value as? String {
                hwdecCurrent = hwdec
            }

        case "hwdec-interop":
            if let interop = value as? String {
                hwdecInterop = interop
            }

        default:
            break
        }
    }

    /// Notify delegate of video size when both dimensions are available
    private func notifyVideoSizeIfReady() {
        guard videoWidth > 0, videoHeight > 0 else { return }
        LoggingService.shared.debug("MPV: Video size detected: \(videoWidth)x\(videoHeight)", category: .mpv)
        delegate?.backend(self, didUpdateVideoSize: videoWidth, height: videoHeight)

        // Update PiP bridge with video aspect ratio for proper window sizing
        #if os(iOS) || os(macOS)
        let aspectRatio = CGFloat(videoWidth) / CGFloat(videoHeight)
        pipBridge?.updateVideoAspectRatio(aspectRatio)
        #endif

        // Update render view with video content dimensions for accurate PiP capture
        // (avoids capturing letterbox/pillarbox black bars)
        #if os(iOS) || os(macOS)
        renderView?.videoContentWidth = videoWidth
        renderView?.videoContentHeight = videoHeight
        #endif

        // Update render view with video FPS for display link frame rate matching
        updateRenderViewFPS()

        // Use video size detection as a fallback signal that video is ready
        // This handles cases where the render view's first-frame callback doesn't fire
        checkAndMarkReadyIfVideoAvailable()
    }

    /// Update render view's video FPS for display link frame rate matching
    private func updateRenderViewFPS() {
        // Use cached container-fps (set via property observation to avoid sync fetch on main thread)
        guard containerFps > 0 else { return }
        renderView?.videoFPS = containerFps
        LoggingService.shared.debug("MPV: Video FPS detected: \(containerFps)", category: .mpv)
    }

    /// Mark as ready if we have video dimensions and aren't seeking
    /// This is a fallback for when the render view's first-frame callback doesn't fire
    private func checkAndMarkReadyIfVideoAvailable() {
        guard !isReady, !isSeeking, videoWidth > 0, videoHeight > 0 else { return }

        LoggingService.shared.debug("MPV: Marking ready based on video size detection", category: .mpv)
        isReady = true
        hasDisplayedVideo = true
        hasStartedPlayback = true

        // Resume playback if we paused for initial seek
        if pendingPlayAfterSeek {
            pendingPlayAfterSeek = false
            mpvClient?.play()
            LoggingService.shared.debug("MPV: Resuming playback after video size detected", category: .mpv)
        }

        // Notify UI that we're ready to show video
        delegate?.backendDidBecomeReady(self)
        delegate?.backend(self, didChangeState: isPlaying ? .playing : .ready)
    }

    /// Mark as ready if this is an audio-only stream detected by MPV
    /// Audio-only streams (like SoundCloud) have no video codec and zero dimensions
    /// This is a fallback when no video frames or dimensions are available
    private func checkAndMarkReadyIfAudioOnlyDetected() {
        guard !isReady, !isSeeking else { return }
        // Detect audio-only: no video codec and no video dimensions from MPV
        guard videoCodec.isEmpty, videoWidth == 0, videoHeight == 0 else { return }
        // Ensure stream metadata is loaded
        guard duration > 0 else { return }

        LoggingService.shared.debug("MPV: Marking ready for audio-only stream (no video track detected)", category: .mpv)
        isReady = true
        hasStartedPlayback = true

        // Resume playback if we paused for initial seek
        if pendingPlayAfterSeek {
            pendingPlayAfterSeek = false
            mpvClient?.play()
            LoggingService.shared.debug("MPV: Resuming playback after audio-only stream ready", category: .mpv)
        }

        delegate?.backendDidBecomeReady(self)
        delegate?.backend(self, didChangeState: isPlaying ? .playing : .ready)
    }

    private func handleEvent(_ event: mpv_event_id) {
        switch event {
        case MPV_EVENT_FILE_LOADED:
            LoggingService.shared.debug("MPV: File loaded", category: .mpv)
            // Log hwdec diagnostics on tvOS (use cached values to avoid sync fetch)
            #if os(tvOS)
            let codec = videoCodec.isEmpty ? "unknown" : videoCodec
            let hwdec = hwdecCurrent.isEmpty ? "none" : hwdecCurrent
            let interop = hwdecInterop.isEmpty ? "none" : hwdecInterop
            LoggingService.shared.debug("MPV: Video codec: \(codec), hwdec-current: \(hwdec), hwdec-interop: \(interop)", category: .mpv)
            #endif
            #if os(iOS) || os(tvOS)
            reactivateAudioSession()
            #endif

        case MPV_EVENT_PLAYBACK_RESTART:
            // PLAYBACK_RESTART fires when seek/load completes and playback can begin
            // When loading with external audio, this signals the audio track is ready
            LoggingService.shared.debug("MPV: Playback restart event (waitingForAudio=\(isWaitingForExternalAudio))", category: .mpv)
            if isWaitingForExternalAudio {
                isWaitingForExternalAudio = false
            }

            // Audio-only streams become ready when playback can begin
            // (no video frames or dimensions to wait for)
            checkAndMarkReadyIfAudioOnlyDetected()

            #if os(iOS) || os(tvOS)
            reactivateAudioSession()
            #endif

        case MPV_EVENT_SEEK:
            LoggingService.shared.debug("MPV: Seek completed", category: .mpv)

        case MPV_EVENT_AUDIO_RECONFIG:
            LoggingService.shared.debug("MPV: Audio reconfigured", category: .mpv)
            #if os(iOS) || os(tvOS)
            reactivateAudioSession()
            #endif

        default:
            break
        }
    }

    // MARK: - Audio Session

    #if os(iOS) || os(tvOS)
    /// Ensures audio session is active for Now Playing integration.
    /// Call this before setting up Now Playing info to ensure the system
    /// recognizes the app as an active media source.
    func ensureAudioSessionActive() {
        reactivateAudioSession()
    }

    /// Re-activates the audio session to ensure Now Playing integration works.
    /// MPV's audio handling can cause iOS to lose track of the active audio source,
    /// so we need to re-activate the session at key playback events.
    private func reactivateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true, options: [])
            LoggingService.shared.debug("MPV: Audio session reactivated for Now Playing", category: .mpv)
        } catch {
            LoggingService.shared.error("MPV: Failed to reactivate audio session: \(error.localizedDescription)", category: .mpv)
        }
    }
    #endif

    private func handleEndFile(reason: MPVEndFileReason) {
        switch reason {
        case .eof:
            LoggingService.shared.debug("MPV: End of file", category: .mpv)
            isPlaying = false
            delegate?.backend(self, didChangeState: .ended)
            delegate?.backendDidFinishPlaying(self)

        case .error:
            // During initial loading, error handling is done in waitForReady() / loadWithRetry()
            // Only report errors here if we're not in initial loading (e.g., mid-playback failure)
            if !isInitialLoading {
                LoggingService.shared.logMPVError("MPV: Playback error")

                // Mid-playback errors are likely due to expired stream URLs
                // Request stream refresh to attempt recovery
                LoggingService.shared.logMPV("MPV: Requesting stream refresh for mid-playback error")
                delegate?.backend(self, didRequestStreamRefresh: currentTime)
            } else {
                LoggingService.shared.debug("MPV: Load error (will retry)", category: .mpv)
            }

        case .stop:
            // During initial loading (e.g., stream switch), the previous file ends with .stop
            // Don't report idle state as we're loading the new stream
            if !isInitialLoading {
                LoggingService.shared.debug("MPV: Playback stopped", category: .mpv)
                isPlaying = false
                delegate?.backend(self, didChangeState: .idle)
            } else {
                LoggingService.shared.debug("MPV: Previous stream stopped (loading new stream)", category: .mpv)
            }

        default:
            break
        }
    }

    // MARK: - Buffer Stall Detection

    /// Start monitoring for buffer stall (buffer stuck at 0% for too long).
    /// Called when paused-for-cache becomes true with 0% buffer during playback.
    private func startBufferStallDetection() {
        // Don't restart if already tracking
        guard bufferStallStartTime == nil else { return }

        bufferStallStartTime = Date()
        LoggingService.shared.debug("MPV: Buffer stall detection started", category: .mpv)

        // Start a periodic check task
        bufferStallCheckTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))  // Check every 5 seconds

                guard let self, !Task.isCancelled else { return }
                guard let stallStart = self.bufferStallStartTime else { return }

                let stallDuration = Date().timeIntervalSince(stallStart)
                // Use cached values (updated via property observation) to avoid sync fetch
                let bufferingState = self.cacheBufferingState
                let isPausedForCache = self.pausedForCache

                // Log stall progress
                LoggingService.shared.debug("MPV: Buffer stall check - duration=\(Int(stallDuration))s, buffering=\(bufferingState)%, pausedForCache=\(isPausedForCache)", category: .mpv)

                // If buffer is still at 0% and paused for cache after timeout, trigger refresh
                if stallDuration >= self.bufferStallTimeout && bufferingState == 0 && isPausedForCache {
                    LoggingService.shared.logMPV("MPV: Buffer stalled for \(Int(stallDuration))s, requesting stream refresh")
                    self.stopBufferStallDetection()
                    self.delegate?.backend(self, didRequestStreamRefresh: self.currentTime)
                    return
                }
            }
        }
    }

    /// Stop buffer stall monitoring.
    /// Called when buffer recovers, playback resumes, or refresh is triggered.
    private func stopBufferStallDetection() {
        guard bufferStallStartTime != nil else { return }

        bufferStallCheckTask?.cancel()
        bufferStallCheckTask = nil
        bufferStallStartTime = nil
        LoggingService.shared.debug("MPV: Buffer stall detection stopped", category: .mpv)
    }
}
