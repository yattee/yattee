//
//  MPVRenderView.swift
//  Yattee
//
//  View for rendering MPV video output using OpenGL ES.
//

import Foundation
import Libmpv
import CoreMedia

#if canImport(UIKit)
import UIKit
import OpenGLES
#elseif canImport(AppKit)
import AppKit
import OpenGL
#endif

// MARK: - Render Error

enum MPVRenderError: LocalizedError {
    case noDevice
    case renderContextFailed(Int32)
    case notInitialized
    case openGLSetupFailed

    var errorDescription: String? {
        switch self {
        case .noDevice:
            return "No graphics device available"
        case .renderContextFailed(let code):
            return "Failed to create render context: \(code)"
        case .notInitialized:
            return "Render view not initialized"
        case .openGLSetupFailed:
            return "Failed to set up OpenGL"
        }
    }
}

// MARK: - OpenGL ES getProcAddress

/// Get OpenGL ES function address for MPV
private func getProcAddress(_ ctx: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    let symbolName = String(cString: name)

    // Get the OpenGL ES framework bundle
    guard let frameworkPath = "/System/Library/Frameworks/OpenGLES.framework" as CFString?,
          let framework = CFBundleCreate(kCFAllocatorDefault, URL(fileURLWithPath: frameworkPath as String) as CFURL) else {
        return nil
    }

    let symbol = CFBundleGetFunctionPointerForName(framework, symbolName as CFString)
    return symbol
}

// MARK: - MPV Render View

#if os(iOS) || os(tvOS)

/// OpenGL ES view for MPV rendering on iOS/tvOS.
final class MPVRenderView: UIView {
    // MARK: - Properties

    private weak var mpvClient: MPVClient?
    private var isSetup = false

    /// Cached time-pos value for PiP presentation timestamps (updated via MPVBackend).
    /// Using cached value avoids blocking render thread with sync mpv_get_property calls.
    private var cachedTimePos: Double = 0

    /// Tracks whether first frame has been rendered (reset on each new load)
    private var hasRenderedFirstFrame = false

    /// Tracks whether MPV has signaled it has a frame ready to render
    private var mpvHasFrameReady = false

    /// Generation counter to invalidate stale frame callbacks when switching videos
    private var frameGeneration: UInt = 0

    /// Callback when first frame is rendered (called once per load)
    var onFirstFrameRendered: (() -> Void)?

    // OpenGL ES
    private var eaglContext: EAGLContext?
    private var framebuffer: GLuint = 0
    private var colorRenderbuffer: GLuint = 0
    private var displayLink: CADisplayLink?

    /// Video frame rate from MPV (used for display link frame rate matching)
    var videoFPS: Double = 60.0 {
        didSet {
            updateDisplayLinkFrameRate()
        }
    }

    /// Current display link target frame rate (for debug overlay)
    var displayLinkTargetFPS: Double {
        videoFPS
    }

    private var renderWidth: GLint = 0
    private var renderHeight: GLint = 0

    /// Last known stable size (for throttling resize events)
    private var lastStableSize: CGSize = .zero
    /// Pending resize work item (for debouncing)
    private var pendingResizeWorkItem: DispatchWorkItem?
    /// Minimum time between framebuffer recreations
    private let resizeDebounceInterval: TimeInterval = 0.1

    /// Dedicated queue for OpenGL rendering (off main thread).
    private let renderQueue = DispatchQueue(label: "stream.yattee.mpv.render", qos: .userInteractive)

    /// Lock for thread-safe access to rendering flag.
    private let renderLock = NSLock()

    /// Flag to prevent queueing multiple render operations.
    private var _isRendering = false
    private var isRendering: Bool {
        get { renderLock.withLock { _isRendering } }
        set { renderLock.withLock { _isRendering = newValue } }
    }

    /// Callback when a new frame is ready (for PiP frame capture).
    var onFrameReady: ((CVPixelBuffer, CMTime) -> Void)?

    /// Callback when view is added to a window (for PiP setup)
    var onDidMoveToWindow: ((UIView) -> Void)?

    // MARK: - PiP Frame Capture

    /// Whether to capture frames for PiP (set by MPVBackend when PiP is active)
    var captureFramesForPiP = false {
        didSet {
            // When frame capture is enabled (e.g., system-triggered PiP), resume rendering if paused
            if captureFramesForPiP && isInBackground {
                isInBackground = false
                displayLink?.isPaused = false
            }
            // When frame capture is disabled and view is not in hierarchy, stop the display link
            // (we kept it running for PiP frame capture, now it can be stopped)
            if !captureFramesForPiP && superview == nil && !isPiPActive {
                stopDisplayLink()
            }
        }
    }

    /// Whether PiP is currently active (skip presenting to main view to save performance)
    var isPiPActive = false {
        didSet {
            // When PiP ends and view is not in hierarchy, stop the display link
            // (we kept it running for PiP frame capture, now it can be stopped)
            if !isPiPActive && superview == nil && !captureFramesForPiP {
                stopDisplayLink()
            }
        }
    }

    /// Frame counter for PiP capture throttling (capture every N frames)
    private var pipFrameCounter = 0

    /// Capture every N frames for PiP
    private let pipCaptureInterval = 1  // Capture every frame for smooth PiP playback

    // Zero-copy texture cache for efficient PiP capture
    private var textureCache: CVOpenGLESTextureCache?
    private var pipFramebuffer: GLuint = 0
    private var pipTexture: CVOpenGLESTexture?
    private var pipPixelBuffer: CVPixelBuffer?
    private var pipCaptureWidth: Int = 0
    private var pipCaptureHeight: Int = 0

    /// Scale factor for PiP capture (1.0 = full res, 0.5 = half res)
    private let pipCaptureScale: CGFloat = 1.0

    // MARK: - Full Resolution Rendering for PiP

    /// Offscreen framebuffer for full-resolution rendering when PiP capture is active.
    /// This allows high-quality PiP even when the view is small (e.g., mini player).
    /// MPV renders to this buffer, then we blit to the display buffer for presentation.
    private var fullResFramebuffer: GLuint = 0
    private var fullResColorRenderbuffer: GLuint = 0
    private var fullResWidth: GLint = 0
    private var fullResHeight: GLint = 0

    /// Maximum resolution for full-res rendering (1080p cap to save memory)
    private let maxFullResHeight: Int = 1080

    /// Whether we're currently using full-resolution rendering mode
    private var isFullResRenderingActive: Bool {
        fullResFramebuffer != 0 && fullResWidth > 0 && fullResHeight > 0
    }

    /// Tracks whether app is in background (to prevent GPU work)
    private var isInBackground = false

    // MARK: - Video Dimensions for PiP

    /// Current video width (actual video content, not view size) - set by backend
    var videoContentWidth: Int = 0

    /// Current video height (actual video content, not view size) - set by backend
    var videoContentHeight: Int = 0

    // MARK: - Layer Class

    override class var layerClass: AnyClass {
        CAEAGLLayer.self
    }

    private var eaglLayer: CAEAGLLayer? {
        layer as? CAEAGLLayer
    }

    // MARK: - Initialization

    init() {
        super.init(frame: .zero)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .black
        contentScaleFactor = UIScreen.main.scale

        // Configure EAGL layer
        // Note: retainedBacking=true is required for glReadPixels to work (for PiP frame capture)
        eaglLayer?.isOpaque = true
        eaglLayer?.drawableProperties = [
            kEAGLDrawablePropertyRetainedBacking: true,
            kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8
        ]

        // Observe app lifecycle to pause GPU work when backgrounded
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func appWillResignActive() {
        // Do NOT pause rendering here - player may still be visible
        // (e.g., Control Center overlay, Notification Center, share sheets)
        // Rendering is only paused when app actually enters background
    }

    /// Timer for background PiP rendering (display link is throttled by iOS in background)
    private var backgroundRenderTimer: Timer?

    @objc private func appDidEnterBackground() {
        MPVLogging.logAppLifecycle("didEnterBackground", isPiPActive: isPiPActive, isRendering: !isInBackground)

        // When entering background with PiP active, use a Timer to drive rendering
        // since iOS throttles display link callbacks during background transition
        if isPiPActive || captureFramesForPiP, isSetup {
            // Stop any existing timer
            backgroundRenderTimer?.invalidate()

            // Use a Timer at ~30fps for 1 second to bridge the iOS throttling gap
            var renderCount = 0
            backgroundRenderTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] timer in
                guard let self else {
                    timer.invalidate()
                    return
                }

                renderCount += 1

                // Stop after ~1 second (30 frames)
                if renderCount > 30 {
                    timer.invalidate()
                    self.backgroundRenderTimer = nil
                    return
                }

                self.renderQueue.async {
                    self.performRender()
                }
            }

            // Ensure timer fires even in background
            RunLoop.main.add(backgroundRenderTimer!, forMode: .common)
            return
        }

        // Pause rendering when entering background (player not visible)
        isInBackground = true
        displayLink?.isPaused = true
        MPVLogging.logDisplayLink("paused", isPaused: true, reason: "enterBackground")

        // Ensure any pending render work completes cleanly
        renderQueue.sync {
            guard let eaglContext else { return }
            let ctxSet = EAGLContext.setCurrent(eaglContext)
            if !ctxSet {
                MPVLogging.warn("EAGLContext.setCurrent failed in appDidEnterBackground")
            }
            glFinish()
            MPVLogging.log("glFinish completed in appDidEnterBackground")
        }
    }

    @objc private func appDidBecomeActive() {
        MPVLogging.logAppLifecycle("didBecomeActive", isPiPActive: isPiPActive, isRendering: !isInBackground)

        // Stop background render timer if running
        backgroundRenderTimer?.invalidate()
        backgroundRenderTimer = nil

        // If PiP was active, we never paused - nothing to resume
        guard isInBackground else {
            MPVLogging.log("appDidBecomeActive: skipping resume (was not in background)")
            return
        }

        isInBackground = false

        // Sync MPV's render state before resuming display link
        // This prevents frame timing issues and dropped frames
        MPVLogging.log("appDidBecomeActive: syncing MPV render state")
        mpvClient?.reportRenderUpdate()

        displayLink?.isPaused = false
        MPVLogging.logDisplayLink("resumed", isPaused: false, reason: "becomeActive")

        // Trigger immediate render to avoid black screen
        if isSetup {
            MPVLogging.log("appDidBecomeActive: triggering immediate render")
            renderQueue.async { [weak self] in
                self?.performRender()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        backgroundRenderTimer?.invalidate()
        stopDisplayLink()

        // Synchronously wait for any pending render to complete, then clean up OpenGL resources
        // on the render queue where the context is valid
        renderQueue.sync {
            guard let eaglContext else { return }
            EAGLContext.setCurrent(eaglContext)
            destroyFullResFramebuffer()
            destroyPiPCapture()
            destroyFramebufferResources()
        }
        eaglContext = nil
    }

    // MARK: - View Lifecycle

    override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)

        MPVLogging.logViewLifecycle("willMove(toSuperview:)", hasSuperview: newSuperview != nil,
            details: "isPiP:\(isPiPActive) captureForPiP:\(captureFramesForPiP)")

        // Stop display link when being removed from superview
        // This breaks the retain cycle (CADisplayLink retains its target)
        // BUT don't stop if PiP is active - we need to keep rendering frames for PiP
        if newSuperview == nil && !isPiPActive && !captureFramesForPiP {
            MPVLogging.logDisplayLink("stop", reason: "removedFromSuperview")
            stopDisplayLink()
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()

        MPVLogging.logViewLifecycle("didMoveToSuperview", hasSuperview: superview != nil,
            details: "isSetup:\(isSetup) displayLink:\(displayLink != nil ? "exists" : "nil") fb:\(framebuffer)")

        // Restart display link and recreate framebuffer when added to a new superview
        // (view may be moved between containers during rotation/layout changes)
        // CAEAGLLayer drawable may be invalidated when view is removed from hierarchy
        if superview != nil && isSetup {
            if displayLink == nil {
                MPVLogging.logDisplayLink("start", reason: "addedToSuperview")
                startDisplayLink()
            }

            // Recreate framebuffer if needed (CAEAGLLayer drawable may have been released)
            if framebuffer == 0 && bounds.size != .zero {
                MPVLogging.log("didMoveToSuperview: recreating framebuffer (was 0)")
                renderQueue.sync {
                    createFramebuffer()
                }
            }

            // Trigger immediate render to show content when view reappears
            // This fixes the black screen after collapse/reopen
            MPVLogging.log("didMoveToSuperview: triggering immediate render")
            renderQueue.async { [weak self] in
                self?.performRender()
            }
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        guard isSetup else { return }

        let currentSize = bounds.size
        let scale = contentScaleFactor
        let expectedFBWidth = Int(currentSize.width * scale)
        let expectedFBHeight = Int(currentSize.height * scale)

        // Check if framebuffer matches current view size
        let framebufferMismatch = abs(Int(renderWidth) - expectedFBWidth) > 2 || abs(Int(renderHeight) - expectedFBHeight) > 2

        // Skip if framebuffer already matches
        guard framebufferMismatch else { return }

        MPVLogging.logTransition("layoutSubviews - size mismatch",
            fromSize: CGSize(width: CGFloat(renderWidth), height: CGFloat(renderHeight)),
            toSize: CGSize(width: CGFloat(expectedFBWidth), height: CGFloat(expectedFBHeight)))

        // Cancel any pending resize
        pendingResizeWorkItem?.cancel()

        // Always recreate framebuffer immediately to ensure video is properly sized
        // This is important during rotation animations
        lastStableSize = bounds.size
        renderQueue.sync {
            destroyFramebuffer()
            createFramebuffer()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        // Notify when view is added to a window (for PiP setup)
        if window != nil {
            onDidMoveToWindow?(self)
        }
    }

    // MARK: - Setup

    /// Set up with an MPV client (async version - moves heavy OpenGL work off main thread).
    func setupAsync(with client: MPVClient) async throws {
        let startTime = Date()
        MPVLogging.log("MPVRenderView.setupAsync: starting")
        
        self.mpvClient = client

        // Create OpenGL ES context on background thread (HEAVY WORK OFF MAIN THREAD)
        // This is the operation that causes 1.5-2s main thread hangs
        MPVLogging.log("setupAsync: creating EAGLContext on background thread")
        let glStartTime = Date()
        
        let context = try await Task.detached(priority: .userInitiated) {
            // This runs on background thread - doesn't block main thread!
            if let ctx = EAGLContext(api: .openGLES3) {
                MPVLogging.log("setupAsync: created OpenGL ES 3.0 context")
                return ctx
            } else if let ctx = EAGLContext(api: .openGLES2) {
                MPVLogging.log("setupAsync: created OpenGL ES 2.0 context (ES3 unavailable)")
                return ctx
            } else {
                MPVLogging.warn("setupAsync: failed to create EAGLContext")
                throw MPVRenderError.openGLSetupFailed
            }
        }.value
        
        let glCreateTime = Date().timeIntervalSince(glStartTime)
        MPVLogging.log("setupAsync: EAGLContext created", 
                      details: "time=\(String(format: "%.3f", glCreateTime))s")
        
        // Back on main thread for UIKit operations
        await MainActor.run {
            self.eaglContext = context
            
            // Make context current
            EAGLContext.setCurrent(context)
            
            // Create framebuffer only if view has valid bounds
            lastStableSize = bounds.size
            if bounds.size != .zero {
                createFramebuffer()
            } else {
                MPVLogging.log("setupAsync: deferring framebuffer creation (bounds are zero)")
            }
        }

        // Create MPV render context with our getProcAddress function
        let success = client.createRenderContext(getProcAddress: getProcAddress)
        if !success {
            MPVLogging.warn("setupAsync: failed to create MPV render context")
            throw MPVRenderError.renderContextFailed(-1)
        }

        // Set up render update callback (for general redraws)
        client.onRenderUpdate = { [weak self] in
            DispatchQueue.main.async {
                self?.setNeedsDisplay()
            }
        }

        // Set up video frame callback (only fires when actual video frame is ready)
        // Capture generation before async to detect stale callbacks from previous video
        client.onVideoFrameReady = { [weak self] in
            guard let self else { return }
            let capturedGeneration = self.frameGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.frameGeneration == capturedGeneration else { return }
                self.mpvHasFrameReady = true
            }
        }

        // Start display link only if framebuffer is ready
        await MainActor.run {
            if framebuffer != 0 {
                startDisplayLink()
            } else {
                MPVLogging.log("setupAsync: deferring displayLink (framebuffer not ready)")
            }
            
            isSetup = true
        }
        
        let totalTime = Date().timeIntervalSince(startTime)
        MPVLogging.log("setupAsync: complete", 
                      details: "total=\(String(format: "%.3f", totalTime))s, gl=\(String(format: "%.3f", glCreateTime))s")
    }

    /// Set up with an MPV client (legacy synchronous version - wraps async).
    func setup(with client: MPVClient) throws {
        // For backward compatibility, wrap async version
        // Note: This will still block, but is only used in non-async contexts
        let semaphore = DispatchSemaphore(value: 0)
        var setupError: Error?
        
        Task {
            do {
                try await setupAsync(with: client)
            } catch {
                setupError = error
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = setupError {
            throw error
        }
    }

    /// Update cached time position for PiP frame timestamps.
    /// Called by MPVBackend when time-pos property changes.
    /// This avoids blocking the render thread with sync mpv_get_property calls.
    func updateTimePosition(_ time: Double) {
        cachedTimePos = time
    }

    // MARK: - Framebuffer

    private func createFramebuffer() {
        guard let eaglContext, let eaglLayer else {
            MPVLogging.warn("createFramebuffer: no context or layer")
            return
        }

        MPVLogging.log("createFramebuffer: starting")

        let ctxSet = EAGLContext.setCurrent(eaglContext)
        if !ctxSet {
            MPVLogging.warn("createFramebuffer: EAGLContext.setCurrent failed")
        }

        // Generate framebuffer
        glGenFramebuffers(1, &framebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)

        // Generate color renderbuffer
        glGenRenderbuffers(1, &colorRenderbuffer)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderbuffer)

        // Allocate storage from EAGL layer
        let storageSuccess = eaglContext.renderbufferStorage(Int(GL_RENDERBUFFER), from: eaglLayer)
        if !storageSuccess {
            MPVLogging.warn("createFramebuffer: renderbufferStorage failed")
            destroyFramebufferResources()
            return
        }

        // Get dimensions
        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_WIDTH), &renderWidth)
        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_HEIGHT), &renderHeight)

        // Check for valid dimensions (view might not have size yet)
        if renderWidth == 0 || renderHeight == 0 {
            MPVLogging.warn("createFramebuffer: invalid dimensions \(renderWidth)x\(renderHeight)")
            destroyFramebufferResources()
            return
        }

        // Attach to framebuffer
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_RENDERBUFFER), colorRenderbuffer)

        // Check status - if incomplete, clean up and retry on layout
        let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        let isComplete = status == GL_FRAMEBUFFER_COMPLETE
        if !isComplete {
            MPVLogging.warn("createFramebuffer: incomplete status=\(status)")
            destroyFramebufferResources()
        } else {
            MPVLogging.logGLState("createFramebuffer complete",
                framebuffer: framebuffer, renderbuffer: colorRenderbuffer,
                width: renderWidth, height: renderHeight,
                contextCurrent: ctxSet, framebufferComplete: true)
        }
    }

    private func destroyFramebuffer() {
        guard let eaglContext else { return }

        MPVLogging.logGLState("destroyFramebuffer",
            framebuffer: framebuffer, renderbuffer: colorRenderbuffer,
            width: renderWidth, height: renderHeight,
            contextCurrent: EAGLContext.current() === eaglContext)

        EAGLContext.setCurrent(eaglContext)
        destroyFramebufferResources()
    }

    /// Destroy framebuffer resources (assumes OpenGL context is already current)
    private func destroyFramebufferResources() {
        if framebuffer != 0 {
            MPVLogging.log("destroyFramebufferResources: deleting FB=\(framebuffer) RB=\(colorRenderbuffer)")
            glDeleteFramebuffers(1, &framebuffer)
            framebuffer = 0
        }

        if colorRenderbuffer != 0 {
            glDeleteRenderbuffers(1, &colorRenderbuffer)
            colorRenderbuffer = 0
        }
    }

    /// Clear the framebuffer to black and present (called when PiP will start)
    func clearMainViewForPiP() {
        renderQueue.async { [weak self] in
            guard let self, let eaglContext = self.eaglContext else { return }

            EAGLContext.setCurrent(eaglContext)
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), self.framebuffer)

            // Clear to black
            glClearColor(0, 0, 0, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

            // Present the black frame
            glBindRenderbuffer(GLenum(GL_RENDERBUFFER), self.colorRenderbuffer)
            eaglContext.presentRenderbuffer(Int(GL_RENDERBUFFER))
        }
    }

    // MARK: - Display Link

    private func startDisplayLink() {
        MPVLogging.logDisplayLink("creating", targetFPS: videoFPS)
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        updateDisplayLinkFrameRate()
        displayLink?.add(to: .main, forMode: .common)
        MPVLogging.logDisplayLink("started", isPaused: displayLink?.isPaused, targetFPS: videoFPS)
    }

    /// Update CADisplayLink preferred frame rate to match video FPS
    /// This reduces unnecessary rendering when video FPS is lower than display refresh
    private func updateDisplayLinkFrameRate() {
        guard let displayLink else { return }

        // Match video FPS with range allowing system optimization
        // Clamp between 24 (common video fps) and 60 (typical display refresh)
        let preferred = Float(min(max(videoFPS, 24.0), 60.0))
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: 24,
            maximum: 60,
            preferred: preferred
        )
    }

    private func stopDisplayLink() {
        MPVLogging.logDisplayLink("stopping", isPaused: displayLink?.isPaused)
        displayLink?.invalidate()
        displayLink = nil
        MPVLogging.logDisplayLink("stopped")
    }

    /// Pause rendering (for sheet collapse/panscan animation)
    /// Note: Does not pause if PiP is active, as frames must continue to be rendered for PiP
    func pauseRendering() {
        let wasPaused = displayLink?.isPaused ?? true
        MPVLogging.logDisplayLink("pauseRendering called", isPaused: wasPaused,
            reason: "isPiP:\(isPiPActive) captureForPiP:\(captureFramesForPiP)")
        LoggingService.shared.debug("MPV RenderView: pauseRendering called - isPiPActive=\(isPiPActive), captureFramesForPiP=\(captureFramesForPiP), displayLink.isPaused was \(wasPaused), hasRenderedFirstFrame=\(hasRenderedFirstFrame), mpvHasFrameReady=\(mpvHasFrameReady)", category: .mpv)
        guard !isPiPActive && !captureFramesForPiP else {
            MPVLogging.log("pauseRendering: skipped (PiP active)")
            LoggingService.shared.debug("MPV RenderView: pauseRendering skipped (PiP active or capturing)", category: .mpv)
            return
        }
        displayLink?.isPaused = true
        MPVLogging.logDisplayLink("paused", isPaused: true, reason: "pauseRendering")
        LoggingService.shared.debug("MPV RenderView: displayLink paused", category: .mpv)
    }

    /// Resume rendering (for sheet expand/panscan animation complete)
    func resumeRendering() {
        let wasPaused = displayLink?.isPaused ?? true
        let hasDisplayLink = displayLink != nil
        MPVLogging.logDisplayLink("resumeRendering called", isPaused: wasPaused,
            reason: "isSetup:\(isSetup) fb:\(framebuffer) hasDisplayLink:\(hasDisplayLink)")
        LoggingService.shared.debug("MPV RenderView: resumeRendering called - displayLink.isPaused was \(wasPaused), isSetup=\(isSetup), hasRenderedFirstFrame=\(hasRenderedFirstFrame), mpvHasFrameReady=\(mpvHasFrameReady)", category: .mpv)

        // If displayLink doesn't exist (was destroyed when view was removed),
        // we can't resume here - didMoveToSuperview will recreate it and trigger render
        guard let displayLink else {
            MPVLogging.log("resumeRendering: no displayLink, will be created when view is added to superview")
            LoggingService.shared.debug("MPV RenderView: resumeRendering skipped - no displayLink", category: .mpv)
            return
        }

        displayLink.isPaused = false
        MPVLogging.logDisplayLink("resumed", isPaused: false, reason: "resumeRendering")
        LoggingService.shared.debug("MPV RenderView: displayLink resumed", category: .mpv)

        // Trigger immediate render to avoid black frame on resume
        if isSetup {
            MPVLogging.log("resumeRendering: triggering immediate render")
            LoggingService.shared.debug("MPV RenderView: triggering immediate render after resume", category: .mpv)
            renderQueue.async { [weak self] in
                self?.performRender()
            }
        }
    }

    /// Reset first frame tracking (call when loading new content)
    func resetFirstFrameTracking() {
        frameGeneration += 1  // Invalidate any pending callbacks from previous video
        hasRenderedFirstFrame = false
        mpvHasFrameReady = false
    }

    /// Clear the render view to black (call when switching videos to hide old frame)
    func clearToBlack() {
        guard eaglContext != nil, framebuffer != 0 else { return }

        // Dispatch to render queue to avoid conflicts with rendering
        renderQueue.async { [weak self] in
            guard let self, let eaglContext = self.eaglContext else { return }

            EAGLContext.setCurrent(eaglContext)
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), self.framebuffer)
            glClearColor(0.0, 0.0, 0.0, 1.0)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

            // Present the cleared frame
            glBindRenderbuffer(GLenum(GL_RENDERBUFFER), self.colorRenderbuffer)
            eaglContext.presentRenderbuffer(Int(GL_RENDERBUFFER))
        }
    }

    // MARK: - Rendering

    @objc private func displayLinkFired() {
        // Skip if not setup, already rendering, or app is in background (GPU work not permitted)
        guard isSetup, !isRendering, !isInBackground else { return }

        isRendering = true

        // Dispatch rendering to background queue to avoid blocking main thread
        renderQueue.async { [weak self] in
            self?.performRender()
        }
    }

    /// Frame counter for periodic verbose logging (avoid spam)
    private var renderFrameLogCounter: UInt64 = 0

    private func performRender() {
        defer { isRendering = false }

        guard let eaglContext, let mpvClient, framebuffer != 0 else {
            // Log when render is skipped due to missing resources (rare but important)
            MPVLogging.warn("performRender: skipped",
                details: "ctx:\(eaglContext != nil) client:\(self.mpvClient != nil) fb:\(framebuffer)")
            return
        }

        // Check render context is available before proceeding
        guard mpvClient.hasRenderContext else {
            MPVLogging.warn("performRender: no render context in mpvClient")
            return
        }

        // Set OpenGL context on this thread
        let ctxSet = EAGLContext.setCurrent(eaglContext)
        if !ctxSet {
            MPVLogging.warn("performRender: EAGLContext.setCurrent FAILED")
        }

        // When PiP capture is active, use full-resolution rendering mode:
        // 1. Render to full-res offscreen buffer (for high-quality PiP capture)
        // 2. Blit to display buffer (for mini player preview)
        // This avoids double-rendering while maintaining quality for both use cases.
        if captureFramesForPiP && videoContentWidth > 0 && videoContentHeight > 0 {
            // Set up or update full-res framebuffer at video resolution (with 1080p cap)
            setupFullResFramebuffer(videoWidth: videoContentWidth, videoHeight: videoContentHeight)

            if isFullResRenderingActive {
                // Render to full-res framebuffer (single render at high quality)
                glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fullResFramebuffer)
                mpvClient.render(fbo: GLint(fullResFramebuffer), width: fullResWidth, height: fullResHeight)

                // Blit from full-res to display framebuffer (downscale for mini player)
                if !isPiPActive && framebuffer != 0 {
                    glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), fullResFramebuffer)
                    glBindFramebuffer(GLenum(GL_DRAW_FRAMEBUFFER), framebuffer)
                    glBlitFramebuffer(
                        0, 0, fullResWidth, fullResHeight,           // src rect (full res)
                        0, 0, renderWidth, renderHeight,              // dst rect (display size)
                        GLbitfield(GL_COLOR_BUFFER_BIT),
                        GLenum(GL_LINEAR)
                    )
                }
            } else {
                // Fallback: render directly to display framebuffer
                glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
                mpvClient.render(fbo: GLint(framebuffer), width: renderWidth, height: renderHeight)
            }
        } else {
            // Normal mode: render directly to display framebuffer
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
            mpvClient.render(fbo: GLint(framebuffer), width: renderWidth, height: renderHeight)
        }

        // Present the renderbuffer (skip when PiP is active - main view is hidden anyway)
        if !isPiPActive {
            glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderbuffer)
            let presented = eaglContext.presentRenderbuffer(Int(GL_RENDERBUFFER))
            if !presented {
                MPVLogging.warn("performRender: presentRenderbuffer FAILED",
                    details: "fb:\(framebuffer) rb:\(colorRenderbuffer) layer:\(layer.bounds) superview:\(superview != nil)")
            }
        }

        // Periodic verbose log (every 300 frames ~= 5 sec at 60fps)
        renderFrameLogCounter += 1
        if renderFrameLogCounter % 300 == 1 {
            MPVLogging.logRender("periodic status", fbo: GLint(framebuffer),
                width: renderWidth, height: renderHeight, success: ctxSet)
        }

        // Capture frame for PiP if enabled
        if captureFramesForPiP && mpvHasFrameReady {
            pipFrameCounter += 1
            if pipFrameCounter >= pipCaptureInterval {
                pipFrameCounter = 0
                captureFrameForPiP()
            }
        }

        // Notify on first frame rendered (only when MPV has actual video data)
        if !hasRenderedFirstFrame && mpvHasFrameReady {
            hasRenderedFirstFrame = true
            MPVLogging.log("performRender: first frame rendered")
            DispatchQueue.main.async { [weak self] in
                self?.onFirstFrameRendered?()
            }
        }
    }

    // MARK: - PiP Frame Capture (Zero-Copy)

    /// Set up the texture cache and PiP framebuffer for zero-copy capture
    private func setupPiPCapture(width: Int, height: Int) {
        guard let eaglContext else { return }

        // Calculate scaled dimensions for PiP (smaller = faster)
        let captureWidth = Int(CGFloat(width) * pipCaptureScale)
        let captureHeight = Int(CGFloat(height) * pipCaptureScale)

        // Skip if dimensions unchanged
        if captureWidth == pipCaptureWidth && captureHeight == pipCaptureHeight && textureCache != nil {
            return
        }

        // Clean up existing resources
        destroyPiPCapture()

        pipCaptureWidth = captureWidth
        pipCaptureHeight = captureHeight

        // Create texture cache
        var cache: CVOpenGLESTextureCache?
        let cacheResult = CVOpenGLESTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            eaglContext,
            nil,
            &cache
        )
        guard cacheResult == kCVReturnSuccess, let cache else {
            LoggingService.shared.warning("MPV PiP: Failed to create texture cache", category: .mpv)
            return
        }
        textureCache = cache

        // Create pixel buffer with IOSurface backing for zero-copy
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: captureWidth,
            kCVPixelBufferHeightKey as String: captureHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            kCVPixelBufferOpenGLESCompatibilityKey as String: true
        ]

        var pixelBuffer: CVPixelBuffer?
        let pbResult = CVPixelBufferCreate(
            kCFAllocatorDefault,
            captureWidth,
            captureHeight,
            kCVPixelFormatType_32BGRA,
            pixelBufferAttributes as CFDictionary,
            &pixelBuffer
        )
        guard pbResult == kCVReturnSuccess, let pixelBuffer else {
            LoggingService.shared.warning("MPV PiP: Failed to create pixel buffer", category: .mpv)
            return
        }
        pipPixelBuffer = pixelBuffer

        // Create GL texture from pixel buffer
        var texture: CVOpenGLESTexture?
        let texResult = CVOpenGLESTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            GLenum(GL_TEXTURE_2D),
            GL_RGBA,
            GLsizei(captureWidth),
            GLsizei(captureHeight),
            GLenum(GL_BGRA),
            GLenum(GL_UNSIGNED_BYTE),
            0,
            &texture
        )
        guard texResult == kCVReturnSuccess, let texture else {
            LoggingService.shared.warning("MPV PiP: Failed to create texture from pixel buffer", category: .mpv)
            return
        }
        pipTexture = texture

        // Create FBO for PiP capture
        glGenFramebuffers(1, &pipFramebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), pipFramebuffer)

        // Attach texture to FBO
        let textureName = CVOpenGLESTextureGetName(texture)
        glFramebufferTexture2D(
            GLenum(GL_FRAMEBUFFER),
            GLenum(GL_COLOR_ATTACHMENT0),
            GLenum(GL_TEXTURE_2D),
            textureName,
            0
        )

        // Verify FBO is complete
        let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if status != GL_FRAMEBUFFER_COMPLETE {
            LoggingService.shared.warning("MPV PiP: Framebuffer incomplete: \(status)", category: .mpv)
            destroyPiPCapture()
            return
        }

        // Restore main framebuffer
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)

        LoggingService.shared.debug("MPV PiP: Zero-copy capture setup complete (\(captureWidth)x\(captureHeight))", category: .mpv)
    }

    /// Clean up PiP capture resources
    private func destroyPiPCapture() {
        // Also destroy the PiP source framebuffer when PiP capture ends
        destroyFullResFramebuffer()

        if pipFramebuffer != 0 {
            glDeleteFramebuffers(1, &pipFramebuffer)
            pipFramebuffer = 0
        }
        pipTexture = nil
        pipPixelBuffer = nil
        if let cache = textureCache {
            CVOpenGLESTextureCacheFlush(cache, 0)
        }
        textureCache = nil
        pipCaptureWidth = 0
        pipCaptureHeight = 0
    }

    // MARK: - Full Resolution Framebuffer

    /// Set up or update the full-resolution offscreen framebuffer.
    /// MPV renders to this buffer when PiP capture is active, then we blit to the display buffer.
    /// This allows high-quality PiP even when the view is small (e.g., mini player).
    private func setupFullResFramebuffer(videoWidth: Int, videoHeight: Int) {
        guard let eaglContext else { return }

        // Calculate target dimensions with 1080p cap to save memory
        let targetWidth: Int
        let targetHeight: Int

        if videoHeight > maxFullResHeight {
            // Scale down proportionally to fit within 1080p height
            let scale = Double(maxFullResHeight) / Double(videoHeight)
            targetWidth = Int(Double(videoWidth) * scale)
            targetHeight = maxFullResHeight
        } else {
            targetWidth = videoWidth
            targetHeight = videoHeight
        }

        // Skip if dimensions unchanged
        guard targetWidth != Int(fullResWidth) || targetHeight != Int(fullResHeight) else {
            return
        }

        // Clean up existing resources
        destroyFullResFramebuffer()

        guard targetWidth > 0 && targetHeight > 0 else { return }

        let ctxSet = EAGLContext.setCurrent(eaglContext)
        if !ctxSet {
            LoggingService.shared.warning("MPV FullRes: EAGLContext.setCurrent failed", category: .mpv)
        }

        // Create framebuffer
        glGenFramebuffers(1, &fullResFramebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fullResFramebuffer)

        // Create color renderbuffer with explicit storage (not from layer)
        glGenRenderbuffers(1, &fullResColorRenderbuffer)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), fullResColorRenderbuffer)
        glRenderbufferStorage(
            GLenum(GL_RENDERBUFFER),
            GLenum(GL_RGBA8),
            GLsizei(targetWidth),
            GLsizei(targetHeight)
        )

        // Attach to framebuffer
        glFramebufferRenderbuffer(
            GLenum(GL_FRAMEBUFFER),
            GLenum(GL_COLOR_ATTACHMENT0),
            GLenum(GL_RENDERBUFFER),
            fullResColorRenderbuffer
        )

        // Verify FBO is complete
        let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if status != GL_FRAMEBUFFER_COMPLETE {
            LoggingService.shared.warning("MPV FullRes: Framebuffer incomplete: \(status)", category: .mpv)
            destroyFullResFramebuffer()
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
            return
        }

        fullResWidth = GLint(targetWidth)
        fullResHeight = GLint(targetHeight)

        // Restore main framebuffer
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)

        LoggingService.shared.debug("MPV FullRes: Created \(targetWidth)x\(targetHeight) framebuffer (video: \(videoWidth)x\(videoHeight))", category: .mpv)
    }

    /// Clean up full-resolution framebuffer resources
    private func destroyFullResFramebuffer() {
        if fullResFramebuffer != 0 {
            glDeleteFramebuffers(1, &fullResFramebuffer)
            fullResFramebuffer = 0
        }
        if fullResColorRenderbuffer != 0 {
            glDeleteRenderbuffers(1, &fullResColorRenderbuffer)
            fullResColorRenderbuffer = 0
        }
        fullResWidth = 0
        fullResHeight = 0
    }

    /// Capture the current framebuffer contents as a CVPixelBuffer for PiP (zero-copy)
    private func captureFrameForPiP() {
        guard let callback = onFrameReady else { return }

        // Verify we have the correct context
        guard EAGLContext.current() === eaglContext else { return }

        // Determine source framebuffer and dimensions
        // Prefer the full-resolution framebuffer if available (for high-quality PiP)
        let sourceFramebuffer: GLuint
        let sourceWidth: GLint
        let sourceHeight: GLint
        let needsLetterboxCrop: Bool

        if isFullResRenderingActive {
            // Use full-resolution framebuffer (rendered at exact video dimensions, no letterbox)
            sourceFramebuffer = fullResFramebuffer
            sourceWidth = fullResWidth
            sourceHeight = fullResHeight
            needsLetterboxCrop = false
        } else {
            // Fall back to display framebuffer (may have letterbox/pillarbox)
            guard renderWidth > 0 && renderHeight > 0 else { return }
            sourceFramebuffer = framebuffer
            sourceWidth = renderWidth
            sourceHeight = renderHeight
            needsLetterboxCrop = true
        }

        // Use actual video dimensions for capture buffer size
        // If video dimensions not set, fall back to source dimensions
        let captureVideoWidth = videoContentWidth > 0 ? videoContentWidth : Int(sourceWidth)
        let captureVideoHeight = videoContentHeight > 0 ? videoContentHeight : Int(sourceHeight)

        // Set up or update capture resources if needed (based on video dimensions)
        setupPiPCapture(width: captureVideoWidth, height: captureVideoHeight)

        guard pipFramebuffer != 0, let pixelBuffer = pipPixelBuffer else { return }

        // Calculate source rect
        var srcX: GLint = 0
        var srcY: GLint = 0
        var srcWidth = sourceWidth
        var srcHeight = sourceHeight

        if needsLetterboxCrop {
            // Calculate the source rect in the framebuffer that contains just the video
            // (excluding letterbox/pillarbox black bars)
            let videoAspect = CGFloat(captureVideoWidth) / CGFloat(captureVideoHeight)
            let viewAspect = CGFloat(sourceWidth) / CGFloat(sourceHeight)

            if videoAspect > viewAspect {
                // Video is wider than view - pillarboxed (black bars on top/bottom)
                let scaledHeight = CGFloat(sourceWidth) / videoAspect
                srcY = GLint((CGFloat(sourceHeight) - scaledHeight) / 2)
                srcHeight = GLint(scaledHeight)
            } else if videoAspect < viewAspect {
                // Video is taller than view - letterboxed (black bars on left/right)
                let scaledWidth = CGFloat(sourceHeight) * videoAspect
                srcX = GLint((CGFloat(sourceWidth) - scaledWidth) / 2)
                srcWidth = GLint(scaledWidth)
            }
        }

        // Bind PiP framebuffer as draw target
        glBindFramebuffer(GLenum(GL_DRAW_FRAMEBUFFER), pipFramebuffer)
        glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), sourceFramebuffer)

        // Blit from source framebuffer to PiP framebuffer (with scaling and vertical flip)
        // Source: video area in source framebuffer (bottom-left origin)
        // Dest: PiP texture (top-left origin, so we flip Y)
        glBlitFramebuffer(
            srcX, srcY, srcX + srcWidth, srcY + srcHeight,        // src rect (video area only)
            0, GLint(pipCaptureHeight), GLint(pipCaptureWidth), 0, // dst rect (flipped Y)
            GLbitfield(GL_COLOR_BUFFER_BIT),
            GLenum(GL_LINEAR)
        )

        // Restore main framebuffer
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)

        // Flush to ensure texture is updated
        glFlush()

        // Use cached time-pos to avoid blocking render thread
        // Updated via updateTimePosition() when property changes (~16ms accuracy @ 60fps)
        let time = cachedTimePos
        let presentationTime = CMTime(seconds: time, preferredTimescale: 90000)

        // Deliver the frame - pixel buffer is already populated via zero-copy
        DispatchQueue.main.async {
            callback(pixelBuffer, presentationTime)
        }
    }

}

#endif
