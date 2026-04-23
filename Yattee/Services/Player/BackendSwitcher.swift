//
//  BackendSwitcher.swift
//  Yattee
//
//  Handles seamless switching between player backends during playback.
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Switch Animation

/// Animation style for backend switching.
enum BackendSwitchAnimation: Sendable {
    case instant        // No animation, immediate swap
    case crossfade      // Crossfade between views
    case slide          // Slide transition

    var duration: TimeInterval {
        switch self {
        case .instant: return 0
        case .crossfade: return 0.3
        case .slide: return 0.4
        }
    }
}

// MARK: - Switch Result

/// Result of a backend switch operation.
struct BackendSwitchResult: Sendable {
    let success: Bool
    let sourceBackend: PlayerBackendType
    let targetBackend: PlayerBackendType
    let timeDrift: TimeInterval  // Difference between expected and actual time after switch
    let switchDuration: TimeInterval  // How long the switch took
}

// MARK: - Backend Switcher Delegate

/// Delegate for switch progress callbacks.
@MainActor
protocol BackendSwitcherDelegate: AnyObject {
    func switcherWillBeginSwitch(from source: PlayerBackendType, to target: PlayerBackendType)
    func switcherDidPrepareTarget(_ switcher: BackendSwitcher)
    func switcherDidCompleteSwitch(_ result: BackendSwitchResult)
    func switcherDidFailSwitch(_ error: Error)
}

// MARK: - Backend Switcher

/// Manages seamless hot-swapping between player backends.
@MainActor
final class BackendSwitcher {
    // MARK: - Properties

    weak var delegate: BackendSwitcherDelegate?

    /// Whether a switch is currently in progress.
    private(set) var isSwitching: Bool = false

    // MARK: - Dependencies

    /// Factory for creating backend instances.
    private let backendFactory: BackendFactory

    /// Settings manager for quality preferences.
    weak var settingsManager: SettingsManager?

    init(backendFactory: BackendFactory, settingsManager: SettingsManager?) {
        self.backendFactory = backendFactory
        self.settingsManager = settingsManager
    }

    // MARK: - Public Methods

    /// Switch from one backend to another during active playback.
    ///
    /// This method:
    /// 1. Captures the current playback state from the source backend
    /// 2. Selects a compatible stream for the target backend
    /// 3. Initializes the target backend and loads the stream
    /// 4. Seeks to the captured position
    /// 5. Waits for the target to be ready
    /// 6. Performs a smooth visual transition
    /// 7. Resumes playback on the target backend
    /// 8. Cleans up the source backend
    ///
    /// - Parameters:
    ///   - source: The currently active backend
    ///   - targetType: The type of backend to switch to
    ///   - streams: Available streams for the current video
    ///   - animation: Animation style for the transition
    /// - Returns: The new active backend
    /// - Throws: BackendError if the switch fails
    func switchBackend(
        from source: any PlayerBackend,
        to targetType: PlayerBackendType,
        streams: [Stream],
        animation: BackendSwitchAnimation = .crossfade
    ) async throws -> any PlayerBackend {
        guard !isSwitching else {
            throw BackendError.switchFailed("Switch already in progress")
        }

        let startTime = Date()
        isSwitching = true

        defer { isSwitching = false }

        LoggingService.shared.logPlayer("Backend switch starting", details: "From \(source.backendType.rawValue) to \(targetType.rawValue)")
        delegate?.switcherWillBeginSwitch(from: source.backendType, to: targetType)

        // Step 1: Capture current state
        let capturedState = source.captureState()

        // Step 2: Find compatible stream for target backend
        guard let selection = selectStream(for: targetType, from: streams) else {
            throw BackendError.switchFailed("No compatible stream found for \(targetType.displayName)")
        }
        let targetStream = selection.video
        let targetAudioStream = selection.audio

        // Step 3: Prepare source for handoff (pause but keep state)
        source.prepareForHandoff()

        // Step 4: Create and initialize target backend
        let target = try backendFactory.createBackend(type: targetType)

        // Step 5: Load stream on target (without autoplay)
        do {
            let useEDL = settingsManager?.mpvUseEDLStreams ?? true
            try await target.load(stream: targetStream, audioStream: targetAudioStream, autoplay: false, useEDL: useEDL)
        } catch {
            // Rollback: resume source backend
            if capturedState.isPlaying {
                source.play()
            }
            throw BackendError.switchFailed("Failed to load stream on target: \(error.localizedDescription)")
        }

        delegate?.switcherDidPrepareTarget(self)

        // Step 6: Seek to captured position
        if capturedState.currentTime > 0 {
            await target.seek(to: capturedState.currentTime, showLoading: false)
        }

        // Step 7: Restore other state (volume, rate, mute)
        target.volume = capturedState.volume
        target.isMuted = capturedState.isMuted
        target.rate = capturedState.rate

        // Step 8: Perform visual transition
        await performTransition(
            from: source,
            to: target,
            animation: animation
        )

        // Step 9: Resume playback if was playing
        if capturedState.isPlaying {
            target.play()
        }

        // Step 10: Stop source backend
        source.stop()

        // Calculate result metrics
        let switchDuration = Date().timeIntervalSince(startTime)
        let timeDrift = abs(target.currentTime - capturedState.currentTime)

        let result = BackendSwitchResult(
            success: true,
            sourceBackend: source.backendType,
            targetBackend: targetType,
            timeDrift: timeDrift,
            switchDuration: switchDuration
        )

        LoggingService.shared.logPlayer("Backend switch completed", details: "Duration: \(String(format: "%.2f", switchDuration))s, drift: \(String(format: "%.3f", timeDrift))s")
        delegate?.switcherDidCompleteSwitch(result)

        return target
    }

    /// Check if switching to a given backend type is possible.
    func canSwitch(to targetType: PlayerBackendType, streams: [Stream]) -> Bool {
        // Check if we have a compatible stream
        selectStream(for: targetType, from: streams) != nil
    }

    // MARK: - Private Methods

    /// Select the best compatible stream for a backend type.
    private func selectStream(for backendType: PlayerBackendType, from streams: [Stream]) -> (video: Stream, audio: Stream?)? {
        let supportedFormats = backendType.supportedFormats
        let preferredQuality = settingsManager?.preferredQuality ?? .auto

        // Separate streams by type
        let videoOnlyStreams = streams.filter { stream in
            guard !stream.isAudioOnly && stream.isVideoOnly else { return false }
            let format = StreamFormat.detect(from: stream)
            return supportedFormats.contains(format)
        }

        let muxedStreams = streams.filter { stream in
            let format = StreamFormat.detect(from: stream)
            guard supportedFormats.contains(format) else { return false }
            return stream.isMuxed || format == .hls || format == .dash
        }

        let audioStreams = streams.filter { $0.isAudioOnly }

        // Get the maximum resolution based on user's quality preference
        let maxResolution = preferredQuality.maxResolution

        // For live streams, always prefer HLS/DASH (designed for live streaming)
        let isLiveStream = streams.contains(where: { $0.isLive })
        if isLiveStream {
            if let hlsStream = muxedStreams.first(where: { StreamFormat.detect(from: $0) == .hls }) {
                return (hlsStream, nil)
            }
            if let dashStream = muxedStreams.first(where: { StreamFormat.detect(from: $0) == .dash }) {
                return (dashStream, nil)
            }
        }

        // Note: For non-live videos, we prefer progressive formats (MP4/WebM) over HLS/DASH
        // because they typically offer better quality. HLS/DASH are only used as last resort.

        // Try to find the best video-only stream + audio
        if !videoOnlyStreams.isEmpty && !audioStreams.isEmpty {
            let filteredVideoStreams: [Stream]
            if let maxRes = maxResolution {
                filteredVideoStreams = videoOnlyStreams.filter { stream in
                    guard let resolution = stream.resolution else { return true }
                    return resolution <= maxRes
                }
            } else {
                filteredVideoStreams = videoOnlyStreams
            }

            // Sort by resolution first, then by codec quality (AV1 > VP9 > H.264)
            let sortedVideo = filteredVideoStreams.sorted { s1, s2 in
                let res1 = s1.resolution ?? .p360
                let res2 = s2.resolution ?? .p360
                if res1 != res2 {
                    return res1 > res2
                }
                // Same resolution - prefer better codec
                return videoCodecPriority(s1.videoCodec) > videoCodecPriority(s2.videoCodec)
            }

            if let bestVideo = sortedVideo.first {
                // Select best audio stream based on preferred language, codec, and bitrate
                let preferredAudioLanguage = settingsManager?.preferredAudioLanguage
                let bestAudio = audioStreams
                    .sorted { stream1, stream2 in
                        // First priority: preferred language or original audio
                        if let preferred = preferredAudioLanguage {
                            // User selected a specific language
                            let lang1 = stream1.audioLanguage ?? ""
                            let lang2 = stream2.audioLanguage ?? ""
                            let matches1 = lang1.hasPrefix(preferred)
                            let matches2 = lang2.hasPrefix(preferred)
                            if matches1 != matches2 { return matches1 }
                        } else {
                            // No preference set - prefer original audio track
                            if stream1.isOriginalAudio != stream2.isOriginalAudio {
                                return stream1.isOriginalAudio
                            }
                        }

                        // Second priority: prefer Opus > AAC for MPV (better quality/compression)
                        let codecPriority1 = audioCodecPriority(stream1.audioCodec)
                        let codecPriority2 = audioCodecPriority(stream2.audioCodec)
                        if codecPriority1 != codecPriority2 {
                            return codecPriority1 > codecPriority2
                        }

                        // Third priority: higher bitrate
                        return (stream1.bitrate ?? 0) > (stream2.bitrate ?? 0)
                    }
                    .first

                if let audio = bestAudio {
                    return (bestVideo, audio)
                }
            }
        }

        // Fallback to muxed streams - prefer progressive formats over HLS/DASH for non-live content
        let filteredMuxed: [Stream]
        if let maxRes = maxResolution {
            filteredMuxed = muxedStreams.filter { stream in
                guard let resolution = stream.resolution else { return true }
                return resolution <= maxRes
            }
        } else {
            filteredMuxed = muxedStreams
        }

        // Sort: prefer non-HLS/DASH (progressive) formats, then by resolution
        let sortedMuxed = filteredMuxed.sorted { s1, s2 in
            let format1 = StreamFormat.detect(from: s1)
            let format2 = StreamFormat.detect(from: s2)
            let isAdaptive1 = format1 == .hls || format1 == .dash
            let isAdaptive2 = format2 == .hls || format2 == .dash

            // Prefer progressive formats for non-live content
            if isAdaptive1 != isAdaptive2 {
                return !isAdaptive1 // non-adaptive (false) comes first
            }
            return (s1.resolution ?? .p360) > (s2.resolution ?? .p360)
        }

        if let bestMuxed = sortedMuxed.first {
            return (bestMuxed, nil)
        }

        // Last resort: any muxed stream (HLS/DASH will be selected here if nothing else available)
        if let anyMuxed = muxedStreams.sorted(by: { ($0.resolution ?? .p360) > ($1.resolution ?? .p360) }).first {
            return (anyMuxed, nil)
        }

        return nil
    }

    /// Returns codec priority for video streams (higher = better for MPV).
    /// AV1 > VP9 > H.264/AVC
    private func videoCodecPriority(_ codec: String?) -> Int {
        guard let codec = codec?.lowercased() else { return 0 }
        if codec.contains("av1") || codec.contains("av01") {
            return 3 // Best compression, modern codec
        } else if codec.contains("vp9") || codec.contains("vp09") {
            return 2 // Good compression, widely supported
        } else if codec.contains("avc") || codec.contains("h264") || codec.contains("h.264") {
            return 1 // Most compatible, less efficient
        }
        return 0
    }

    /// Returns codec priority for audio streams (higher = better for MPV).
    /// Opus > AAC
    private func audioCodecPriority(_ codec: String?) -> Int {
        guard let codec = codec?.lowercased() else { return 0 }
        if codec.contains("opus") {
            return 2 // Best quality/compression ratio
        } else if codec.contains("aac") || codec.contains("mp4a") {
            return 1 // Good compatibility
        }
        return 0
    }

    /// Perform visual transition between backends.
    private func performTransition(
        from source: any PlayerBackend,
        to target: any PlayerBackend,
        animation: BackendSwitchAnimation
    ) async {
        guard animation != .instant else { return }

        #if canImport(UIKit)
        guard let sourceView = source.playerView,
              let targetView = target.playerView,
              let containerView = sourceView.superview else {
            return
        }

        // Add target view behind source
        targetView.frame = containerView.bounds
        targetView.alpha = 0
        containerView.insertSubview(targetView, belowSubview: sourceView)

        // Animate transition
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            UIView.animate(withDuration: animation.duration, animations: {
                switch animation {
                case .crossfade:
                    sourceView.alpha = 0
                    targetView.alpha = 1

                case .slide:
                    sourceView.transform = CGAffineTransform(translationX: -sourceView.bounds.width, y: 0)
                    targetView.alpha = 1

                case .instant:
                    break
                }
            }, completion: { _ in
                sourceView.removeFromSuperview()
                continuation.resume()
            })
        }

        #elseif canImport(AppKit)
        guard let sourceView = source.playerView,
              let targetView = target.playerView,
              let containerView = sourceView.superview else {
            return
        }

        // Add target view
        targetView.frame = containerView.bounds
        targetView.alphaValue = 0
        containerView.addSubview(targetView, positioned: .below, relativeTo: sourceView)

        // Animate transition
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = animation.duration
                sourceView.animator().alphaValue = 0
                targetView.animator().alphaValue = 1
            }, completionHandler: {
                sourceView.removeFromSuperview()
                continuation.resume()
            })
        }
        #endif
    }
}

// MARK: - Backend Factory

/// Factory for creating player backend instances with pre-warming pool.
@MainActor
final class BackendFactory {
    /// Pool of pre-warmed backends ready for instant playback (1 per type)
    private var backendPool: [PlayerBackendType: any PlayerBackend] = [:]
    
    /// Statistics for monitoring pool efficiency
    private var poolHits = 0
    private var poolMisses = 0
    
    /// Create or retrieve a pre-warmed backend.
    func createBackend(type: PlayerBackendType) throws -> any PlayerBackend {
        // Try to get from pool first
        if let backend = backendPool[type] {
            backendPool[type] = nil  // Remove from pool
            poolHits += 1
            
            LoggingService.shared.debug("BackendFactory: pool hit for \(type.displayName) (hits=\(poolHits), misses=\(poolMisses))", category: .mpv)
            
            // Immediately start warming a replacement in background
            Task {
                await prewarmBackend(type: type)
            }
            
            return backend
        }
        
        poolMisses += 1
        LoggingService.shared.debug("BackendFactory: pool miss for \(type.displayName) (hits=\(poolHits), misses=\(poolMisses))", category: .mpv)
        
        // Create new backend and begin setup
        let backend = createBackendInstance(type: type)
        if let mpvBackend = backend as? MPVBackend {
            mpvBackend.beginSetup()
        }
        return backend
    }
    
    /// Create a backend instance (without pool).
    private func createBackendInstance(type: PlayerBackendType) -> any PlayerBackend {
        switch type {
        case .mpv:
            return MPVBackend()
        }
    }
    
    /// Pre-warm a backend and add to pool.
    func prewarmBackend(type: PlayerBackendType) async {
        let startTime = Date()
        LoggingService.shared.debug("BackendFactory: pre-warming \(type.displayName)", category: .mpv)
        
        let backend = await MainActor.run {
            createBackendInstance(type: type)
        }
        
        // Begin async setup
        if let mpvBackend = backend as? MPVBackend {
            await MainActor.run {
                mpvBackend.beginSetup()
            }
            // Wait for setup to complete
            do {
                try await mpvBackend.waitForSetup()
            } catch {
                LoggingService.shared.debug("BackendFactory: pre-warm failed for \(type.displayName): \(error)", category: .mpv)
                return
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        LoggingService.shared.debug("BackendFactory: \(type.displayName) pre-warmed in \(String(format: "%.3f", duration))s", category: .mpv)
        
        // Add to pool (only if slot is empty - don't accumulate)
        await MainActor.run {
            if backendPool[type] == nil {
                backendPool[type] = backend
                LoggingService.shared.debug("BackendFactory: \(type.displayName) added to pool", category: .mpv)
            } else {
                LoggingService.shared.debug("BackendFactory: \(type.displayName) pool already full, discarding", category: .mpv)
            }
        }
    }
    
    /// Pre-warm all available backends in parallel.
    func prewarmAllBackends() async {
        let startTime = Date()
        LoggingService.shared.debug("BackendFactory: pre-warming all backends", category: .mpv)
        
        // Pre-warm in parallel
        await withTaskGroup(of: Void.self) { group in
            for type in availableBackends {
                group.addTask {
                    await self.prewarmBackend(type: type)
                }
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        LoggingService.shared.debug("BackendFactory: all backends pre-warmed in \(String(format: "%.3f", duration))s", category: .mpv)
    }
    
    /// Drain the pool (called on memory warning).
    func drainPool() {
        let count = backendPool.count
        backendPool.removeAll()
        LoggingService.shared.debug("BackendFactory: pool drained (\(count) backends released)", category: .mpv)
    }

    /// Check if a backend type is available on this platform.
    func isAvailable(_ type: PlayerBackendType) -> Bool {
        switch type {
        case .mpv:
            return true
        }
    }

    /// Get all available backend types.
    var availableBackends: [PlayerBackendType] {
        PlayerBackendType.allCases.filter { isAvailable($0) }
    }
}
