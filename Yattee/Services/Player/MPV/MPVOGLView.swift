//
//  MPVOGLView.swift
//  Yattee
//
//  NSView that hosts MPVOpenGLLayer and manages CADisplayLink for macOS.
//  Moves all rendering off the main thread for smooth UI during video playback.
//

#if os(macOS)

import AppKit
import CoreMedia
import CoreVideo
import Libmpv

// MARK: - MPVOGLView

/// View for MPV video rendering on macOS.
/// Hosts an MPVOpenGLLayer and manages CADisplayLink for vsync timing.
final class MPVOGLView: NSView {
    // MARK: - Properties

    /// The OpenGL layer that handles rendering.
    private(set) lazy var videoLayer: MPVOpenGLLayer = {
        MPVOpenGLLayer(videoView: self)
    }()

    /// Reference to the MPV client.
    private weak var mpvClient: MPVClient?

    /// CADisplayLink for frame timing and vsync (macOS 14+).
    private var displayLink: CADisplayLink?

    /// Whether the view has been uninitialized.
    private var isUninited = false

    /// Lock for thread-safe access to isUninited.
    private let uninitLock = NSLock()

    // MARK: - First Frame Tracking

    /// Tracks whether MPV has signaled it has a frame ready to render.
    var mpvHasFrameReady = false

    /// Callback when first frame is rendered.
    var onFirstFrameRendered: (() -> Void)? {
        get { videoLayer.onFirstFrameRendered }
        set { videoLayer.onFirstFrameRendered = newValue }
    }

    // MARK: - Video Info

    /// Video frame rate from MPV (for debug overlay).
    var videoFPS: Double = 60.0

    /// Actual display link frame rate.
    var displayLinkActualFPS: Double = 60.0

    /// Current display link target frame rate (for debug overlay).
    var displayLinkTargetFPS: Double {
        displayLinkActualFPS
    }

    // MARK: - PiP Properties (forwarded to layer)

    /// Whether to capture frames for PiP.
    var captureFramesForPiP: Bool {
        get { videoLayer.captureFramesForPiP }
        set { videoLayer.captureFramesForPiP = newValue }
    }

    /// Whether PiP is currently active.
    var isPiPActive: Bool {
        get { videoLayer.isPiPActive }
        set { videoLayer.isPiPActive = newValue }
    }

    /// Callback when a new frame is ready for PiP.
    var onFrameReady: ((CVPixelBuffer, CMTime) -> Void)? {
        get { videoLayer.onFrameReady }
        set { videoLayer.onFrameReady = newValue }
    }

    /// Video content width (actual video dimensions for letterbox cropping).
    var videoContentWidth: Int {
        get { videoLayer.videoContentWidth }
        set { videoLayer.videoContentWidth = newValue }
    }

    /// Video content height (actual video dimensions for letterbox cropping).
    var videoContentHeight: Int {
        get { videoLayer.videoContentHeight }
        set { videoLayer.videoContentHeight = newValue }
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    /// Convenience initializer with zero frame.
    convenience init() {
        self.init(frame: .zero)
    }

    private func commonInit() {
        // Set up layer-backed view
        wantsLayer = true
        layer = videoLayer

        // Configure layer properties
        videoLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0

        // Configure view properties
        autoresizingMask = [.width, .height]
    }

    deinit {
        uninit()
    }

    // MARK: - Setup

    /// Set up with an MPV client.
    func setup(with client: MPVClient) throws {
        self.mpvClient = client

        // Set up the layer
        try videoLayer.setup(with: client)

        // Start display link
        startDisplayLink()
    }

    /// Async setup variant.
    func setupAsync(with client: MPVClient) async throws {
        try setup(with: client)
    }

    // MARK: - View Lifecycle

    override var isOpaque: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let window {
            // Recreate display link for new window
            stopDisplayLink()
            startDisplayLink()

            // Update contents scale for new window
            videoLayer.contentsScale = window.backingScaleFactor
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()

        // Update contents scale when backing properties change
        if let scale = window?.backingScaleFactor {
            videoLayer.contentsScale = scale
        }

        // Update display refresh rate
        updateDisplayRefreshRate()
    }

    override func draw(_ dirtyRect: NSRect) {
        // No-op - the layer handles all drawing
    }

    // MARK: - CADisplayLink Management

    func startDisplayLink() {
        guard displayLink == nil else { return }

        // Create display link using modern API (macOS 14+)
        displayLink = displayLink(target: self, selector: #selector(displayLinkFired(_:)))
        displayLink?.add(to: .main, forMode: .common)

        // Update refresh rate info
        updateDisplayRefreshRate()

        LoggingService.shared.debug("MPVOGLView: display link started", category: .mpv)
    }

    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil

        LoggingService.shared.debug("MPVOGLView: display link stopped", category: .mpv)
    }

    @objc private func displayLinkFired(_ sender: CADisplayLink) {
        // Check if uninited (thread-safe)
        uninitLock.lock()
        let uninited = isUninited
        uninitLock.unlock()

        guard !uninited else { return }

        // Report frame swap to MPV for vsync timing
        mpvClient?.reportSwap()
    }

    /// Update display link for the current display.
    func updateDisplayLink() {
        // With CADisplayLink, we just need to update the refresh rate info
        updateDisplayRefreshRate()
    }

    /// Update the cached display refresh rate.
    private func updateDisplayRefreshRate() {
        guard let screen = window?.screen else {
            displayLinkActualFPS = 60.0
            return
        }

        // Get refresh rate from screen
        displayLinkActualFPS = Double(screen.maximumFramesPerSecond)
        if displayLinkActualFPS <= 0 {
            displayLinkActualFPS = 60.0
        }

        LoggingService.shared.debug("MPVOGLView: display refresh rate: \(displayLinkActualFPS) Hz", category: .mpv)
    }

    // MARK: - Public Methods

    /// Reset first frame tracking (call when loading new content).
    func resetFirstFrameTracking() {
        mpvHasFrameReady = false
        videoLayer.resetFirstFrameTracking()
    }

    /// Clear the view to black.
    func clearToBlack() {
        videoLayer.clearToBlack()
    }

    /// Pause rendering.
    func pauseRendering() {
        // For now, just stop triggering updates
        // The layer will still respond to explicit update() calls
    }

    /// Resume rendering.
    func resumeRendering() {
        videoLayer.update(force: true)
    }

    /// Update cached time position for PiP timestamps.
    func updateTimePosition(_ time: Double) {
        videoLayer.updateTimePosition(time)
    }

    /// Clear the main view for PiP transition (stub for now).
    func clearMainViewForPiP() {
        clearToBlack()
    }

    /// Update PiP target render size - forces recreation of PiP capture resources.
    func updatePiPTargetSize(_ size: CMVideoDimensions) {
        videoLayer.updatePiPTargetSize(size)
    }

    // MARK: - Cleanup

    /// Uninitialize the view and release resources.
    func uninit() {
        uninitLock.lock()
        defer { uninitLock.unlock() }

        guard !isUninited else { return }
        isUninited = true

        stopDisplayLink()
        videoLayer.uninit()

        // Note: onFirstFrameRendered and onFrameReady are forwarded to videoLayer,
        // and videoLayer.uninit() clears them
    }
}

#endif
