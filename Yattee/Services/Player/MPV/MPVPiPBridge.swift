//
//  MPVPiPBridge.swift
//  Yattee
//
//  Native Picture-in-Picture support for MPV using AVSampleBufferDisplayLayer.
//

#if os(iOS) || os(macOS)
import AVKit
import CoreMedia
import CoreVideo
import os

#if os(iOS)
import UIKit
typealias PlatformView = UIView
typealias PlatformColor = UIColor
#elseif os(macOS)
import AppKit
typealias PlatformView = NSView
typealias PlatformColor = NSColor
#endif

/// Bridges MPV video output to AVPictureInPictureController using AVSampleBufferDisplayLayer.
/// This enables native PiP for MPV-rendered content.
@MainActor
final class MPVPiPBridge: NSObject {
    // MARK: - Properties

    private let sampleBufferLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController?
    private weak var mpvBackend: MPVBackend?

    /// Whether PiP is currently active.
    var isPiPActive: Bool {
        pipController?.isPictureInPictureActive ?? false
    }

    /// Whether PiP is possible (controller exists and is not nil).
    var isPiPPossible: Bool {
        pipController?.isPictureInPicturePossible ?? false
    }

    /// Callback for when user wants to restore from PiP to main app.
    var onRestoreUserInterface: (() async -> Void)?

    /// Callback for when PiP active status changes.
    var onPiPStatusChanged: ((Bool) -> Void)?

    /// Callback for when PiP will start (for early UI updates like clearing main view)
    var onPiPWillStart: (() -> Void)?

    /// Callback for when PiP will stop (to resume main view rendering before animation ends)
    var onPiPWillStop: (() -> Void)?

    /// Callback for when PiP stops without restore (user clicked close button in PiP)
    var onPiPDidStopWithoutRestore: (() -> Void)?

    /// Callback for when isPictureInPicturePossible changes
    var onPiPPossibleChanged: ((Bool) -> Void)?

    /// Callback for when PiP render size changes (for resizing capture buffers)
    var onPiPRenderSizeChanged: ((CMVideoDimensions) -> Void)?

    /// KVO observation for isPictureInPicturePossible
    private var pipPossibleObservation: NSKeyValueObservation?

    /// Current PiP render size from AVPictureInPictureController
    private var currentPiPRenderSize: CMVideoDimensions?

    /// Current video aspect ratio (width / height)
    private var videoAspectRatio: CGFloat = 16.0 / 9.0

    /// Track whether restore was requested before PiP stopped
    private var restoreWasRequested = false

    #if os(macOS)
    /// Timer to periodically update layer frame to match superlayer
    private var layerResizeTimer: Timer?
    /// Track if we've logged the PiP window hierarchy already
    private var hasLoggedPiPHierarchy = false
    /// Views we've hidden that need to be restored before PiP cleanup.
    /// Uses weak references to avoid retaining AVKit internal views that get deallocated
    /// when the PiP window closes, which would cause crashes in objc_release.
    private var hiddenPiPViews = NSHashTable<NSView>.weakObjects()
    #endif

    // MARK: - Format Descriptions

    private var currentFormatDescription: CMVideoFormatDescription?
    private var lastPresentationTime: CMTime = .zero

    /// Timebase for controlling sample buffer display timing
    private var timebase: CMTimebase?

    /// Cache last pixel buffer to re-enqueue during close animation
    private var lastPixelBuffer: CVPixelBuffer?

    // MARK: - Playback State (Thread-Safe for nonisolated delegate methods)

    /// Cached duration for PiP time range (thread-safe)
    private let _duration = OSAllocatedUnfairLock(initialState: 0.0)
    /// Cached paused state for PiP (thread-safe)
    private let _isPaused = OSAllocatedUnfairLock(initialState: false)

    /// Update cached playback state from backend (call periodically)
    func updatePlaybackState(duration: Double, currentTime: Double, isPaused: Bool) {
        _duration.withLock { $0 = duration }
        _isPaused.withLock { $0 = isPaused }

        // Update timebase with current playback position
        if let timebase {
            let time = CMTime(seconds: currentTime, preferredTimescale: 90000)
            CMTimebaseSetTime(timebase, time: time)
        }
    }

    // MARK: - Setup

    /// Set up PiP with the given MPV backend and container view.
    /// - Parameters:
    ///   - backend: The MPV backend to connect to
    ///   - containerView: The view to embed the sample buffer layer in
    func setup(backend: MPVBackend, in containerView: PlatformView) {
        self.mpvBackend = backend

        // Configure sample buffer layer
        sampleBufferLayer.frame = containerView.bounds
        #if os(macOS)
        // On macOS, use resize to fill the entire area (ignoring aspect ratio)
        // This works around AVKit's PiP window sizing that includes title bar height
        sampleBufferLayer.videoGravity = .resize
        sampleBufferLayer.contentsGravity = .resize
        // Enable auto-resizing to fill superlayer
        sampleBufferLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        #else
        sampleBufferLayer.videoGravity = .resizeAspect
        sampleBufferLayer.contentsGravity = .resizeAspect
        #endif
        sampleBufferLayer.backgroundColor = PlatformColor.clear.cgColor

        // Set up timebase for controlling playback timing
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &timebase
        )
        if let timebase {
            self.timebase = timebase
            sampleBufferLayer.controlTimebase = timebase
            CMTimebaseSetRate(timebase, rate: 1.0)
            CMTimebaseSetTime(timebase, time: .zero)
        }

        // IMPORTANT: Hide the layer during normal playback so it doesn't cover
        // the OpenGL rendering. It will be shown when PiP is active.
        sampleBufferLayer.isHidden = true

        // Layer must be in view hierarchy for PiP to work, but can be hidden
        #if os(iOS)
        containerView.layer.addSublayer(sampleBufferLayer)
        #elseif os(macOS)
        // On macOS, add the layer to the container view's layer.
        // The warning about NSHostingController is unavoidable with AVSampleBufferDisplayLayer PiP,
        // but it doesn't affect functionality - the PiP window works correctly.
        containerView.wantsLayer = true
        if let layer = containerView.layer {
            // Add on top - the layer is hidden during normal playback anyway
            layer.addSublayer(sampleBufferLayer)
        }
        sampleBufferLayer.frame = containerView.bounds
        #endif

        // Create content source for sample buffer playback
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: sampleBufferLayer,
            playbackDelegate: self
        )

        // Create PiP controller
        pipController = AVPictureInPictureController(contentSource: contentSource)
        pipController?.delegate = self

        // Observe isPictureInPicturePossible changes via KVO
        // Note: Don't use .initial here - callbacks aren't set up yet when setup() is called.
        // Use notifyPiPPossibleState() after setting up callbacks.
        pipPossibleObservation = pipController?.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] _, change in
            let isPossible = change.newValue ?? false
            Task { @MainActor [weak self] in
                self?.onPiPPossibleChanged?(isPossible)
            }
        }

        #if os(iOS)
        // Observe app lifecycle to handle background transitions while PiP is active
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        #endif

        LoggingService.shared.debug("MPVPiPBridge: Setup complete", category: .mpv)
    }

    /// Manually notify current isPiPPossible state.
    /// Call this after setting up onPiPPossibleChanged callback.
    func notifyPiPPossibleState() {
        onPiPPossibleChanged?(isPiPPossible)
    }

    /// Update the video aspect ratio for proper PiP sizing.
    /// Call this when video dimensions are known or change.
    /// - Parameter aspectRatio: Video width divided by height (e.g., 16/9 = 1.777...)
    func updateVideoAspectRatio(_ aspectRatio: CGFloat) {
        guard aspectRatio > 0 else { return }
        videoAspectRatio = aspectRatio

        #if os(macOS)
        // On macOS, update layer bounds to match aspect ratio
        // This helps AVKit size the PiP window correctly
        let currentBounds = sampleBufferLayer.bounds
        let newHeight = currentBounds.width / aspectRatio
        let newBounds = CGRect(x: 0, y: 0, width: currentBounds.width, height: newHeight)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sampleBufferLayer.bounds = newBounds
        CATransaction.commit()

        LoggingService.shared.debug("MPVPiPBridge: Updated aspect ratio to \(aspectRatio), layer bounds: \(newBounds)", category: .mpv)
        #else
        // On iOS, don't modify bounds when PiP is inactive - this causes frame misalignment
        // (negative Y offset) which breaks the system's PiP restore UI positioning.
        // AVKit gets the aspect ratio from the enqueued video frames.

        // If PiP is active and video changed, calculate and update the layer frame.
        // The superlayer bounds don't update during PiP (view hierarchy hidden),
        // so we calculate the correct frame based on screen width and aspect ratio.
        if isPiPActive {
            // Detect significant aspect ratio change - if so, flush buffer to force AVKit
            // to re-read video dimensions from the new format description
            let currentBounds = sampleBufferLayer.bounds
            if currentBounds.height > 0 {
                let previousRatio = currentBounds.width / currentBounds.height
                let ratioChange = abs(aspectRatio - previousRatio) / previousRatio

                if ratioChange > 0.05 { // >5% change indicates new video
                    // Flush buffer and clear format description to force AVKit to re-read dimensions
                    sampleBufferLayer.sampleBufferRenderer.flush()
                    currentFormatDescription = nil

                    LoggingService.shared.debug("MPVPiPBridge: Flushed buffer for aspect ratio change \(previousRatio) -> \(aspectRatio)", category: .mpv)
                }
            }

            let screenWidth = UIScreen.main.bounds.width
            // Calculate height based on aspect ratio, capped to leave room for details
            let maxHeight = UIScreen.main.bounds.height * 0.6 // Leave 40% for details
            let calculatedHeight = screenWidth / aspectRatio
            let height = min(calculatedHeight, maxHeight)
            let width = height < calculatedHeight ? height * aspectRatio : screenWidth
            let newFrame = CGRect(x: 0, y: 0, width: width, height: height)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sampleBufferLayer.frame = newFrame
            sampleBufferLayer.bounds = CGRect(origin: .zero, size: newFrame.size)
            CATransaction.commit()
            pipController?.invalidatePlaybackState()
            LoggingService.shared.debug("MPVPiPBridge: Updated aspect ratio to \(aspectRatio), calculated layer frame during PiP: \(newFrame)", category: .mpv)
        } else {
            LoggingService.shared.debug("MPVPiPBridge: Updated aspect ratio to \(aspectRatio) (bounds unchanged on iOS)", category: .mpv)
        }
        #endif
    }

    #if os(iOS)
    @objc private func appWillResignActive() {
        guard isPiPActive, let timebase else { return }

        // Sync timebase and pre-buffer frames before iOS throttles/suspends
        if let currentTime = mpvBackend?.currentTime {
            let time = CMTime(seconds: currentTime, preferredTimescale: 90000)
            CMTimebaseSetTime(timebase, time: time)
        }
        CMTimebaseSetRate(timebase, rate: 1.0)
        preBufferFramesForBackgroundTransition()
    }

    @objc private func appDidEnterBackground() {
        guard isPiPActive, let timebase else { return }

        // Ensure timebase is synced and running
        if let currentTime = mpvBackend?.currentTime {
            let time = CMTime(seconds: currentTime, preferredTimescale: 90000)
            CMTimebaseSetTime(timebase, time: time)
        }
        CMTimebaseSetRate(timebase, rate: 1.0)

        // Pre-buffer additional frames as secondary buffer
        preBufferFramesForBackgroundTransition()
    }

    /// Pre-buffer frames with future timestamps to bridge iOS background suspension.
    /// Note: iOS suspends app code for ~300-400ms during background transition.
    /// Pre-buffered frames show the same content but keep the layer fed.
    private func preBufferFramesForBackgroundTransition() {
        guard let pixelBuffer = lastPixelBuffer,
              let formatDescription = currentFormatDescription,
              let timebase else { return }

        let currentTimebaseTime = CMTimebaseGetTime(timebase)
        let frameInterval = CMTime(value: 1, timescale: 30)
        var currentPTS = currentTimebaseTime

        // Pre-enqueue 30 frames (~1 second) to bridge the iOS suspension gap
        for _ in 0..<30 {
            currentPTS = CMTimeAdd(currentPTS, frameInterval)

            var sampleTimingInfo = CMSampleTimingInfo(
                duration: frameInterval,
                presentationTimeStamp: currentPTS,
                decodeTimeStamp: .invalid
            )

            var sampleBuffer: CMSampleBuffer?
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescription: formatDescription,
                sampleTiming: &sampleTimingInfo,
                sampleBufferOut: &sampleBuffer
            )

            guard let sampleBuffer else { continue }

            if sampleBufferLayer.sampleBufferRenderer.status != .failed {
                sampleBufferLayer.sampleBufferRenderer.enqueue(sampleBuffer)
            }
        }

        lastPresentationTime = currentPTS
    }
    #endif

    /// Update the layer frame when container bounds change.
    /// On macOS, the frame should be relative to the window's content view.
    func updateLayerFrame(_ frame: CGRect) {
        sampleBufferLayer.frame = frame
    }

    #if os(macOS)
    /// Update the layer frame based on container view's bounds.
    /// Call this on macOS when the container view's size changes.
    func updateLayerFrame(for containerView: NSView) {
        sampleBufferLayer.frame = containerView.bounds
    }
    #endif

    /// Move the sample buffer layer to a new container view.
    /// This is needed when transitioning from fullscreen to PiP,
    /// as the layer must be in a visible window hierarchy.
    func moveLayer(to containerView: PlatformView) {
        sampleBufferLayer.removeFromSuperlayer()
        sampleBufferLayer.frame = containerView.bounds
        #if os(iOS)
        containerView.layer.addSublayer(sampleBufferLayer)
        #elseif os(macOS)
        containerView.wantsLayer = true
        containerView.layer?.addSublayer(sampleBufferLayer)
        #endif
    }

    /// Clean up and release resources.
    func cleanup() {
        NotificationCenter.default.removeObserver(self)
        pipPossibleObservation?.invalidate()
        pipPossibleObservation = nil
        lastPixelBuffer = nil
        pipController?.stopPictureInPicture()
        pipController = nil
        sampleBufferLayer.removeFromSuperlayer()
        sampleBufferLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
        mpvBackend = nil
    }

    /// Flush the sample buffer to clear any displayed frame.
    /// Call this when stopping playback to prevent stale frames when reusing backend.
    func flushBuffer() {
        sampleBufferLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
        frameCount = 0
    }

    // MARK: - Frame Enqueueing

    /// Track frame count for logging
    private var frameCount = 0

    /// Enqueue a video frame from MPV for display.
    /// This is called by MPV's render callback when a frame is ready.
    /// - Parameters:
    ///   - pixelBuffer: The decoded video frame as CVPixelBuffer
    ///   - presentationTime: The presentation timestamp for this frame
    func enqueueFrame(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        frameCount += 1

        // Log first few frames and then periodically
        if frameCount <= 3 || frameCount % 60 == 0 {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            LoggingService.shared.debug("MPVPiPBridge: Enqueue frame #\(frameCount), size: \(width)x\(height), layer status: \(sampleBufferLayer.sampleBufferRenderer.status.rawValue)", category: .mpv)
        }

        // Create format description if needed or if dimensions changed
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        if currentFormatDescription == nil ||
           CMVideoFormatDescriptionGetDimensions(currentFormatDescription!).width != Int32(width) ||
           CMVideoFormatDescriptionGetDimensions(currentFormatDescription!).height != Int32(height) {
            var formatDescription: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &formatDescription
            )
            currentFormatDescription = formatDescription
        }

        guard let formatDescription = currentFormatDescription else { return }

        // Create sample timing info
        var sampleTimingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30), // Approximate frame duration
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )

        // Create sample buffer
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &sampleTimingInfo,
            sampleBufferOut: &sampleBuffer
        )

        guard let sampleBuffer else { return }

        // Cache the pixel buffer for re-enqueuing during close animation
        lastPixelBuffer = pixelBuffer

        // Enqueue on sample buffer layer
        if sampleBufferLayer.sampleBufferRenderer.status != .failed {
            sampleBufferLayer.sampleBufferRenderer.enqueue(sampleBuffer)
            lastPresentationTime = presentationTime
        } else {
            // Flush and retry if layer is in failed state
            sampleBufferLayer.sampleBufferRenderer.flush()
            sampleBufferLayer.sampleBufferRenderer.enqueue(sampleBuffer)
        }
    }

    /// Re-enqueue the last frame to prevent placeholder from showing
    private func reenqueueLastFrame() {
        guard let pixelBuffer = lastPixelBuffer,
              let formatDescription = currentFormatDescription else { return }

        // Increment presentation time slightly to avoid duplicate timestamps
        let newPresentationTime = CMTimeAdd(lastPresentationTime, CMTime(value: 1, timescale: 30))

        var sampleTimingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: newPresentationTime,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &sampleTimingInfo,
            sampleBufferOut: &sampleBuffer
        )

        guard let sampleBuffer else { return }

        if sampleBufferLayer.sampleBufferRenderer.status != .failed {
            sampleBufferLayer.sampleBufferRenderer.enqueue(sampleBuffer)
            lastPresentationTime = newPresentationTime
        }
    }

    // MARK: - PiP Control

    /// Start Picture-in-Picture.
    func startPiP() {
        guard let pipController, pipController.isPictureInPicturePossible else {
            LoggingService.shared.warning("MPVPiPBridge: PiP not possible", category: .mpv)
            return
        }

        #if os(iOS)
        // Update layer frame to match current superlayer bounds before starting PiP.
        // This ensures the frame is correct for the current video's player area.
        if let superlayer = sampleBufferLayer.superlayer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sampleBufferLayer.frame = superlayer.bounds
            sampleBufferLayer.bounds = CGRect(origin: .zero, size: superlayer.bounds.size)
            CATransaction.commit()
            LoggingService.shared.debug("MPVPiPBridge: Updated layer frame before PiP: \(superlayer.bounds)", category: .mpv)
        }
        #endif

        // Show the layer before starting PiP - it needs to be visible for PiP to work
        sampleBufferLayer.isHidden = false

        pipController.startPictureInPicture()
        LoggingService.shared.debug("MPVPiPBridge: Starting PiP", category: .mpv)
    }

    /// Stop Picture-in-Picture.
    func stopPiP() {
        pipController?.stopPictureInPicture()
        // Layer will be hidden in didStopPictureInPicture delegate
        LoggingService.shared.debug("MPVPiPBridge: Stopping PiP", category: .mpv)
    }

    /// Toggle Picture-in-Picture.
    func togglePiP() {
        if isPiPActive {
            stopPiP()
        } else {
            startPiP()
        }
    }

    /// Invalidate and update the playback state in PiP window.
    func invalidatePlaybackState() {
        pipController?.invalidatePlaybackState()
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension MPVPiPBridge: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        // Update cached state immediately for responsive UI
        _isPaused.withLock { $0 = !playing }

        Task { @MainActor in
            // Update timebase rate
            if let timebase {
                CMTimebaseSetRate(timebase, rate: playing ? 1.0 : 0.0)
            }

            if playing {
                mpvBackend?.play()
            } else {
                mpvBackend?.pause()
            }
            // Notify PiP system that state changed
            pipController?.invalidatePlaybackState()
        }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        let duration = _duration.withLock { $0 }
        // Return actual duration if known
        if duration > 0 {
            return CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 90000))
        }
        // Fallback to a reasonable default until we know the actual duration
        return CMTimeRange(start: .zero, duration: CMTime(seconds: 3600, preferredTimescale: 90000))
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        _isPaused.withLock { $0 }
    }

    // Optional: Handle skip by interval (completion handler style to avoid compiler crash)
    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping @Sendable () -> Void
    ) {
        Task { @MainActor in
            let currentTime = mpvBackend?.currentTime ?? 0
            let newTime = currentTime + skipInterval.seconds
            await mpvBackend?.seek(to: max(0, newTime))
            completionHandler()
        }
    }

    // Optional: Whether to prohibit background audio
    nonisolated func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        false // Allow background audio
    }

    // Required: Handle render size changes
    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
        Task { @MainActor in
            currentPiPRenderSize = newRenderSize
            onPiPRenderSizeChanged?(newRenderSize)
            LoggingService.shared.debug("MPVPiPBridge: PiP render size changed to \(newRenderSize.width)x\(newRenderSize.height)", category: .mpv)
        }
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension MPVPiPBridge: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            // Reset PiP render size - will be updated by didTransitionToRenderSize
            currentPiPRenderSize = nil
            // Reset restore flag - will be set if user clicks restore button
            restoreWasRequested = false
            // Show the sample buffer layer when PiP starts
            sampleBufferLayer.isHidden = false

            #if os(macOS)
            // Ensure our layer has no background that could cause black areas
            sampleBufferLayer.backgroundColor = nil

            // Hide other sublayers (like _NSOpenGLViewBackingLayer) that would cover our video
            if let superlayer = sampleBufferLayer.superlayer,
               let sublayers = superlayer.sublayers {
                for layer in sublayers where layer !== sampleBufferLayer {
                    layer.isHidden = true
                    LoggingService.shared.debug("MPVPiPBridge: Hiding layer \(type(of: layer)) for PiP", category: .mpv)
                }
            }

            // Clear backgrounds on parent layers that could cause black areas
            // The container view's backing layer often has a black background
            var currentLayer: CALayer? = sampleBufferLayer.superlayer
            var depth = 0
            while let layer = currentLayer {
                let layerType = String(describing: type(of: layer))
                if layer.backgroundColor != nil {
                    LoggingService.shared.debug("MPVPiPBridge: Clearing background on \(layerType) at depth \(depth)", category: .mpv)
                    layer.backgroundColor = nil
                }
                currentLayer = layer.superlayer
                depth += 1
                if depth > 5 { break } // Don't go too far up
            }
            #endif

            // Notify to clear main view immediately
            onPiPWillStart?()
            LoggingService.shared.debug("MPVPiPBridge: Will start PiP", category: .mpv)
        }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            onPiPStatusChanged?(true)
            // Debug: Log layer frame and bounds
            LoggingService.shared.debug("MPVPiPBridge: Did start PiP - layer frame: \(sampleBufferLayer.frame), bounds: \(sampleBufferLayer.bounds), videoGravity: \(sampleBufferLayer.videoGravity.rawValue)", category: .mpv)

            #if os(macOS)
            // Start timer to update layer frame to match PiP window
            startLayerResizeTimer()
            #endif
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            // Hide the layer again since PiP failed
            sampleBufferLayer.isHidden = true

            #if os(macOS)
            // Unhide other sublayers that we hid when trying to start PiP
            if let superlayer = sampleBufferLayer.superlayer,
               let sublayers = superlayer.sublayers {
                for layer in sublayers where layer !== sampleBufferLayer {
                    layer.isHidden = false
                }
            }
            #endif

            onPiPStatusChanged?(false)
            LoggingService.shared.logMPVError("MPVPiPBridge: Failed to start PiP", error: error)
        }
    }

    nonisolated func pictureInPictureControllerWillStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            #if os(macOS)
            // Restore hidden views BEFORE cleanup to prevent crashes
            restoreHiddenPiPViews()
            #endif

            // Pre-enqueue multiple copies of the last frame to ensure buffer has content
            // throughout the entire close animation (typically ~0.3-0.5 seconds)
            for _ in 0..<30 {
                reenqueueLastFrame()
            }

            // Resume main view rendering before animation ends
            // Keep sampleBufferLayer visible and receiving frames during close animation
            // to avoid showing the "video is playing in picture in picture" placeholder
            onPiPWillStop?()

            LoggingService.shared.debug("MPVPiPBridge: Will stop PiP, pre-enqueued frames", category: .mpv)
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            #if os(macOS)
            // Stop layer resize timer
            stopLayerResizeTimer()

            // Unhide other sublayers that we hid when PiP started
            if let superlayer = sampleBufferLayer.superlayer,
               let sublayers = superlayer.sublayers {
                for layer in sublayers where layer !== sampleBufferLayer {
                    layer.isHidden = false
                }
            }
            #endif

            // Hide the sample buffer layer when PiP stops
            sampleBufferLayer.isHidden = true

            // Clear cached pixel buffer
            lastPixelBuffer = nil

            onPiPStatusChanged?(false)

            // If restore wasn't requested, notify that PiP stopped without restore
            // (user clicked X button instead of restore button)
            if !restoreWasRequested {
                LoggingService.shared.debug("MPVPiPBridge: Did stop PiP without restore (close button)", category: .mpv)
                onPiPDidStopWithoutRestore?()
            } else {
                LoggingService.shared.debug("MPVPiPBridge: Did stop PiP (with restore)", category: .mpv)
            }
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            // Mark that restore was requested - didStopPictureInPicture will check this
            restoreWasRequested = true
            LoggingService.shared.debug("MPVPiPBridge: Restore requested", category: .mpv)
            await onRestoreUserInterface?()
            completionHandler(true)
        }
    }
}

// MARK: - macOS Layer Resize Timer

#if os(macOS)
extension MPVPiPBridge {
    /// Start a timer to periodically resize the layer to match the PiP window.
    /// This is needed on macOS because AVKit doesn't automatically resize the layer.
    func startLayerResizeTimer() {
        stopLayerResizeTimer()

        // Check immediately
        updateLayerFrameToMatchPiPWindow()

        // Then check periodically
        layerResizeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateLayerFrameToMatchPiPWindow()
            }
        }
    }

    /// Stop the layer resize timer.
    func stopLayerResizeTimer() {
        layerResizeTimer?.invalidate()
        layerResizeTimer = nil
    }

    /// Find the PiP window by enumerating all windows.
    private func findPiPWindow() -> NSWindow? {
        // Get all windows in the app
        let allWindows = NSApplication.shared.windows

        for window in allWindows {
            let className = String(describing: type(of: window))
            // PiP windows on macOS are typically named PIPPanelWindow or similar
            if className.contains("PIP") || className.contains("PiP") || className.contains("Picture") {
                LoggingService.shared.debug("MPVPiPBridge: Found PiP window: \(className), frame: \(window.frame)", category: .mpv)
                return window
            }
        }

        // If no PiP window found in our app, it might be owned by AVKit framework
        // Try to find it via CGWindowListCopyWindowInfo
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        if let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            for windowInfo in windowList {
                if let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                   ownerName.contains("Picture") || ownerName.contains("PiP") {
                    LoggingService.shared.debug("MPVPiPBridge: Found PiP via CGWindowList: \(ownerName)", category: .mpv)
                }
                if let windowName = windowInfo[kCGWindowName as String] as? String {
                    if windowName.contains("Picture") || windowName.contains("PiP") {
                        // Found it, but CGWindowInfo doesn't give us NSWindow
                        if let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
                           let width = bounds["Width"] as? CGFloat,
                           let height = bounds["Height"] as? CGFloat {
                            LoggingService.shared.debug("MPVPiPBridge: PiP window bounds from CGWindowList: \(width)x\(height)", category: .mpv)
                        }
                    }
                }
            }
        }

        return nil
    }

    /// Recursively log view hierarchy for debugging
    private func logViewHierarchy(_ view: NSView, depth: Int) {
        let indent = String(repeating: "  ", count: depth)
        let viewType = String(describing: type(of: view))
        let layerInfo: String
        if let layer = view.layer {
            let bgColor = layer.backgroundColor != nil ? "has bg" : "no bg"
            let clips = layer.masksToBounds ? "clips" : "no clip"
            layerInfo = "layer: \(layer.frame), \(bgColor), \(clips)"
        } else {
            layerInfo = "no layer"
        }
        LoggingService.shared.debug("MPVPiPBridge: \(indent)[\(depth)] \(viewType) frame: \(view.frame), \(layerInfo)", category: .mpv)

        // Check sublayers
        if let layer = view.layer {
            for sublayer in layer.sublayers ?? [] {
                let sublayerType = String(describing: type(of: sublayer))
                let subBg = sublayer.backgroundColor != nil ? "HAS BG" : "no bg"
                let subClips = sublayer.masksToBounds ? "clips" : "no clip"
                LoggingService.shared.debug("MPVPiPBridge: \(indent)  -> sublayer: \(sublayerType), frame: \(sublayer.frame), \(subBg), \(subClips)", category: .mpv)
            }
        }

        // Recurse into subviews (limit depth to avoid spam)
        if depth < 6 {
            for subview in view.subviews {
                logViewHierarchy(subview, depth: depth + 1)
            }
        }
    }

    /// Fix the mispositioned AVPictureInPictureCALayerHostView that causes the black bar
    private func fixPiPLayerHostViewPosition(in pipWindow: NSWindow) {
        guard let contentView = pipWindow.contentView else { return }

        // Find the AVPictureInPictureCALayerHostView which is positioned incorrectly
        findAndFixLayerHostView(in: contentView, windowBounds: contentView.bounds)
    }

    private func findAndFixLayerHostView(in view: NSView, windowBounds: CGRect) {
        let viewType = String(describing: type(of: view))

        // AVPictureInPictureCALayerHostView contains the SOURCE view content (our OpenGL view)
        // It's positioned incorrectly and shows the black background from our app
        // We want to HIDE this completely - we only need the AVSampleBufferDisplayLayerContentLayer
        if viewType.contains("AVPictureInPictureCALayerHostView") {
            if !view.isHidden {
                LoggingService.shared.debug("MPVPiPBridge: Hiding \(viewType) - it contains source view with black bg", category: .mpv)
                view.isHidden = true
                view.layer?.isHidden = true
                // Track this view so we can unhide it before cleanup
                hiddenPiPViews.add(view)
            }
        }

        // Disable clipping on content layers
        if viewType.contains("AVPictureInPictureSampleBufferDisplayLayerHostView") {
            // Disable clipping on this view and its sublayers
            view.layer?.masksToBounds = false
            for sublayer in view.layer?.sublayers ?? [] {
                sublayer.masksToBounds = false
            }
        }

        // Recurse
        for subview in view.subviews {
            findAndFixLayerHostView(in: subview, windowBounds: windowBounds)
        }
    }

    /// Restore any views we hid to prevent crashes during cleanup
    private func restoreHiddenPiPViews() {
        let views = hiddenPiPViews.allObjects
        let count = views.count
        for view in views {
            view.isHidden = false
            view.layer?.isHidden = false
        }
        hiddenPiPViews.removeAllObjects()
        LoggingService.shared.debug("MPVPiPBridge: Restored \(count) hidden PiP views", category: .mpv)
    }

    /// Update the sample buffer layer's frame to match the PiP window size.
    private func updateLayerFrameToMatchPiPWindow() {
        // Try to find the PiP window
        if let pipWindow = findPiPWindow() {
            // Get the content view bounds (excludes title bar)
            let windowSize = pipWindow.contentView?.bounds.size ?? pipWindow.frame.size

            // Log detailed PiP window view hierarchy once
            if !hasLoggedPiPHierarchy, let contentView = pipWindow.contentView {
                hasLoggedPiPHierarchy = true
                LoggingService.shared.debug("MPVPiPBridge: ===== PiP Window View Hierarchy =====", category: .mpv)
                LoggingService.shared.debug("MPVPiPBridge: Window frame: \(pipWindow.frame), contentView frame: \(contentView.frame)", category: .mpv)
                logViewHierarchy(contentView, depth: 0)
            }

            // Fix mispositioned internal AVKit views that cause the black bar
            fixPiPLayerHostViewPosition(in: pipWindow)

            let newFrame = CGRect(origin: .zero, size: windowSize)

            if sampleBufferLayer.frame.size != newFrame.size {
                LoggingService.shared.debug("MPVPiPBridge: Resizing layer to match PiP window: \(sampleBufferLayer.frame) -> \(newFrame)", category: .mpv)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                sampleBufferLayer.frame = newFrame
                CATransaction.commit()
            }
        } else {
            // Fallback: try to match superlayer
            guard let superlayer = sampleBufferLayer.superlayer else { return }
            let superBounds = superlayer.bounds
            if sampleBufferLayer.frame != superBounds {
                LoggingService.shared.debug("MPVPiPBridge: Resizing layer to match superlayer: \(sampleBufferLayer.frame) -> \(superBounds)", category: .mpv)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                sampleBufferLayer.frame = superBounds
                CATransaction.commit()
            }
        }
    }
}
#endif

#endif
