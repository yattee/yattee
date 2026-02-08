//
//  MPVOpenGLLayer.swift
//  Yattee
//
//  CAOpenGLLayer subclass for MPV rendering on macOS.
//  Renders on a background thread to avoid blocking the main thread.
//

#if os(macOS)

import AppKit
import OpenGL.GL
import OpenGL.GL3
import Libmpv
import CoreMedia
import CoreVideo

// MARK: - OpenGL Pixel Format Attributes

private let glFormatBase: [CGLPixelFormatAttribute] = [
    kCGLPFAOpenGLProfile,
    CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
    kCGLPFAAccelerated,
    kCGLPFADoubleBuffer,
    kCGLPFAAllowOfflineRenderers,
    CGLPixelFormatAttribute(0)
]

private let glFormat10Bit: [CGLPixelFormatAttribute] = [
    kCGLPFAOpenGLProfile,
    CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
    kCGLPFAAccelerated,
    kCGLPFADoubleBuffer,
    kCGLPFAAllowOfflineRenderers,
    kCGLPFAColorSize,
    CGLPixelFormatAttribute(64),
    kCGLPFAColorFloat,
    CGLPixelFormatAttribute(0)
]

// MARK: - MPVOpenGLLayer

/// OpenGL layer for MPV rendering on macOS.
/// Renders on a background thread to avoid blocking the main thread during video playback.
final class MPVOpenGLLayer: CAOpenGLLayer {
    // MARK: - Properties

    /// Reference to the video view that hosts this layer.
    private weak var videoView: MPVOGLView?

    /// Reference to the MPV client for rendering.
    private weak var mpvClient: MPVClient?

    /// Dedicated queue for OpenGL rendering (off main thread).
    private let renderQueue = DispatchQueue(label: "stream.yattee.mpv.render", qos: .userInteractive)

    /// CGL context for OpenGL rendering.
    private let cglContext: CGLContextObj

    /// CGL pixel format used to create the context.
    private let cglPixelFormat: CGLPixelFormatObj

    /// Lock to single-thread calls to `display`.
    private let displayLock = NSRecursiveLock()

    /// Buffer depth (8 for standard, 16 for 10-bit).
    private var bufferDepth: GLint = 8

    /// Current framebuffer object ID.
    private var fbo: GLint = 1

    /// When `true` the frame needs to be rendered.
    private var needsFlip = false
    private let needsFlipLock = NSLock()

    /// When `true` drawing will proceed even if mpv indicates nothing needs to be done.
    private var forceDraw = false
    private let forceDrawLock = NSLock()

    /// Whether the layer has been set up with an MPV client.
    private var isSetup = false

    /// Whether the layer is being cleaned up.
    private var isUninited = false

    /// Tracks whether first frame has been rendered.
    private var hasRenderedFirstFrame = false

    /// Callback when first frame is rendered.
    var onFirstFrameRendered: (() -> Void)?

    // MARK: - PiP Capture Properties

    /// Zero-copy texture cache for efficient PiP capture.
    private var textureCache: CVOpenGLTextureCache?

    /// Framebuffer for PiP capture.
    private var pipFramebuffer: GLuint = 0

    /// Texture from CVOpenGLTextureCache (bound to pixel buffer).
    private var pipTexture: CVOpenGLTexture?

    /// Pixel buffer for PiP capture (IOSurface-backed for zero-copy).
    private var pipPixelBuffer: CVPixelBuffer?

    /// Current PiP capture dimensions.
    private var pipCaptureWidth: Int = 0
    private var pipCaptureHeight: Int = 0

    /// Offscreen render FBO for PiP mode (when layer isn't visible).
    private var pipRenderFBO: GLuint = 0

    /// Render texture for PiP mode FBO.
    private var pipRenderTexture: GLuint = 0

    /// Dimensions of the PiP render FBO.
    private var pipRenderWidth: Int = 0
    private var pipRenderHeight: Int = 0

    /// Whether to capture frames for PiP.
    var captureFramesForPiP = false

    /// Whether PiP is currently active.
    var isPiPActive = false

    /// Callback when a frame is ready for PiP.
    var onFrameReady: ((CVPixelBuffer, CMTime) -> Void)?

    /// Video content width (actual video, not view size) - for letterbox/pillarbox cropping.
    var videoContentWidth: Int = 0

    /// Video content height (actual video, not view size) - for letterbox/pillarbox cropping.
    var videoContentHeight: Int = 0

    /// Cached time position for PiP presentation timestamps.
    private var cachedTimePos: Double = 0

    /// Frame counter for PiP logging.
    private var pipFrameCount: UInt64 = 0

    // MARK: - Initialization

    /// Creates an MPVOpenGLLayer for the given video view.
    init(videoView: MPVOGLView) {
        self.videoView = videoView

        // Create pixel format (try 10-bit first, fall back to 8-bit)
        let (pixelFormat, depth) = MPVOpenGLLayer.createPixelFormat()
        self.cglPixelFormat = pixelFormat
        self.bufferDepth = depth

        // Create OpenGL context
        self.cglContext = MPVOpenGLLayer.createContext(pixelFormat: pixelFormat)

        super.init()

        // Configure layer
        autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backgroundColor = NSColor.black.cgColor
        isOpaque = true

        // Set color space to device RGB (sRGB) to prevent color space conversion issues
        // Without this, macOS may apply unwanted gamma/color transformations
        colorspace = CGColorSpaceCreateDeviceRGB()

        // Use appropriate contents format for bit depth
        if bufferDepth > 8 {
            contentsFormat = .RGBA16Float
        }

        // Start with synchronous drawing disabled (we control updates via renderQueue)
        isAsynchronous = false

        let colorDepth = bufferDepth
        Task { @MainActor in
            LoggingService.shared.debug("MPVOpenGLLayer: initialized with \(colorDepth)-bit color", category: .mpv)
        }
    }

    /// Creates a shadow copy of the layer (called by Core Animation during scale changes).
    override init(layer: Any) {
        let previousLayer = layer as! MPVOpenGLLayer
        self.videoView = previousLayer.videoView
        self.mpvClient = previousLayer.mpvClient
        self.cglPixelFormat = previousLayer.cglPixelFormat
        self.cglContext = previousLayer.cglContext
        self.bufferDepth = previousLayer.bufferDepth
        self.isSetup = previousLayer.isSetup

        super.init(layer: layer)

        autoresizingMask = previousLayer.autoresizingMask
        backgroundColor = previousLayer.backgroundColor
        isOpaque = previousLayer.isOpaque
        colorspace = previousLayer.colorspace
        contentsFormat = previousLayer.contentsFormat
        isAsynchronous = previousLayer.isAsynchronous

        Task { @MainActor in
            LoggingService.shared.debug("MPVOpenGLLayer: created shadow copy", category: .mpv)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        uninit()
    }

    // MARK: - Setup

    /// Set up the layer with an MPV client.
    func setup(with client: MPVClient) throws {
        guard !isSetup else {
            Task { @MainActor in
                LoggingService.shared.debug("MPVOpenGLLayer: already set up", category: .mpv)
            }
            return
        }

        self.mpvClient = client

        // Make context current for render context creation
        CGLSetCurrentContext(cglContext)

        // Create MPV render context
        let success = client.createRenderContext(getProcAddress: macOSGetProcAddress)
        guard success else {
            Task { @MainActor in
                LoggingService.shared.error("MPVOpenGLLayer: failed to create MPV render context", category: .mpv)
            }
            throw MPVRenderError.renderContextFailed(-1)
        }

        // Store CGL context in client for locking
        client.setOpenGLContext(cglContext)

        // Set up render update callback
        client.onRenderUpdate = { [weak self] in
            self?.update()
        }

        // Note: We don't set onVideoFrameReady here anymore.
        // The mpvHasFrameReady flag is now set in draw() when we actually render a frame.
        // This is more accurate and avoids the issue where the render callback
        // was consuming the frame-ready flag before canDraw() could check it.

        isSetup = true
        Task { @MainActor in
            LoggingService.shared.debug("MPVOpenGLLayer: setup complete", category: .mpv)
        }
    }

    /// Clean up resources.
    func uninit() {
        guard !isUninited else { return }
        isUninited = true

        // Clean up PiP capture resources
        destroyPiPCapture()
        onFrameReady = nil

        // Clear callbacks
        mpvClient?.onRenderUpdate = nil
        mpvClient?.onVideoFrameReady = nil
        onFirstFrameRendered = nil

        Task { @MainActor in
            LoggingService.shared.debug("MPVOpenGLLayer: uninit complete", category: .mpv)
        }
    }

    // MARK: - CAOpenGLLayer Overrides

    override func canDraw(
        inCGLContext ctx: CGLContextObj,
        pixelFormat pf: CGLPixelFormatObj,
        forLayerTime t: CFTimeInterval,
        displayTime ts: UnsafePointer<CVTimeStamp>?
    ) -> Bool {
        guard !isUninited, isSetup else { return false }

        // Check if force draw is requested or MPV has a frame ready
        let force = forceDrawLock.withLock { forceDraw }
        if force { return true }

        return mpvClient?.shouldRenderUpdateFrame() ?? false
    }

    override func draw(
        inCGLContext ctx: CGLContextObj,
        pixelFormat pf: CGLPixelFormatObj,
        forLayerTime t: CFTimeInterval,
        displayTime ts: UnsafePointer<CVTimeStamp>?
    ) {
        guard !isUninited, isSetup, let mpvClient else { return }

        // Reset flags
        needsFlipLock.withLock { needsFlip = false }
        forceDrawLock.withLock { forceDraw = false }

        // Clear the buffer
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

        // Get current FBO binding and viewport dimensions
        var currentFBO: GLint = 0
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &currentFBO)

        var viewport: [GLint] = [0, 0, 0, 0]
        glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)

        let width = viewport[2]
        let height = viewport[3]

        guard width > 0, height > 0 else { return }

        // Use the detected FBO (or fallback to cached)
        if currentFBO != 0 {
            fbo = currentFBO
        }

        // Render the frame
        mpvClient.renderWithDepth(
            fbo: fbo,
            width: width,
            height: height,
            depth: bufferDepth
        )

        glFlush()

        // Capture frame for PiP if enabled
        if captureFramesForPiP {
            captureFrameForPiP(viewWidth: width, viewHeight: height, mainFBO: fbo)
        }

        // Mark that we've rendered a frame (for first-frame tracking)
        if let videoView, !videoView.mpvHasFrameReady {
            DispatchQueue.main.async { [weak self] in
                self?.videoView?.mpvHasFrameReady = true
            }
        }

        // Notify on first frame
        if !hasRenderedFirstFrame {
            hasRenderedFirstFrame = true
            DispatchQueue.main.async { [weak self] in
                self?.onFirstFrameRendered?()
            }
        }
    }

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        cglPixelFormat
    }

    override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj {
        cglContext
    }

    /// Trigger a display update (dispatched to render queue).
    override func display() {
        displayLock.lock()
        defer { displayLock.unlock() }

        let isUpdate = needsFlipLock.withLock { needsFlip }

        if Thread.isMainThread {
            super.display()
        } else {
            // When not on main thread, use explicit transaction
            CATransaction.begin()
            super.display()
            CATransaction.commit()
        }

        // Flush any implicit transaction
        CATransaction.flush()

        // Handle cases where canDraw/draw weren't called by AppKit but MPV has frames ready.
        // This can happen when the view is in another space or not visible.
        // We need to tell MPV to skip rendering to prevent frame buildup.
        let stillNeedsFlip = needsFlipLock.withLock { needsFlip }
        guard isUpdate && stillNeedsFlip else { return }

        // If we get here, display() was called but draw() wasn't invoked by AppKit.
        // Need to do a skip render to keep MPV's frame queue moving.
        guard let mpvClient, let renderContext = mpvClient.mpvRenderContext,
              mpvClient.shouldRenderUpdateFrame() else { return }

        // Must lock OpenGL context before calling mpv render functions
        mpvClient.lockAndSetOpenGLContext()
        defer { mpvClient.unlockOpenGLContext() }

        var skip: CInt = 1
        withUnsafeMutablePointer(to: &skip) { skipPtr in
            var params: [mpv_render_param] = [
                mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: skipPtr),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
            ]
            _ = params.withUnsafeMutableBufferPointer { paramsPtr in
                mpv_render_context_render(renderContext, paramsPtr.baseAddress)
            }
        }
    }

    // MARK: - Public Methods

    /// Request a render update (called when MPV signals a new frame).
    func update(force: Bool = false) {
        renderQueue.async { [weak self] in
            guard let self, !self.isUninited else { return }

            if force {
                self.forceDrawLock.withLock { self.forceDraw = true }
            }
            self.needsFlipLock.withLock { self.needsFlip = true }

            // When PiP is active, the layer may not be visible so CAOpenGLLayer.draw()
            // won't be called by Core Animation. We need to manually render and capture
            // frames for PiP.
            if self.isPiPActive && self.captureFramesForPiP {
                self.renderForPiP()
            } else {
                self.display()
            }
        }
    }

    /// Render a frame specifically for PiP capture (when main view is hidden).
    private func renderForPiP() {
        guard !isUninited, isSetup, let mpvClient else { return }
        guard mpvClient.shouldRenderUpdateFrame() else { return }

        // Lock and set OpenGL context
        CGLLockContext(cglContext)
        CGLSetCurrentContext(cglContext)
        defer { CGLUnlockContext(cglContext) }

        // Use video dimensions for render size, or fall back to reasonable defaults
        let width = GLint(videoContentWidth > 0 ? videoContentWidth : 1920)
        let height = GLint(videoContentHeight > 0 ? videoContentHeight : 1080)

        guard width > 0, height > 0 else { return }

        // Set up offscreen render FBO if needed
        setupPiPRenderFBO(width: Int(width), height: Int(height))

        guard pipRenderFBO != 0 else { return }

        // Bind our render FBO
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), pipRenderFBO)
        glViewport(0, 0, width, height)

        // Render the frame to our FBO
        mpvClient.renderWithDepth(
            fbo: GLint(pipRenderFBO),
            width: width,
            height: height,
            depth: bufferDepth
        )

        glFlush()

        // Report frame swap for vsync timing - important for smooth PiP playback
        mpvClient.reportSwap()

        // Capture frame for PiP
        captureFrameForPiP(viewWidth: width, viewHeight: height, mainFBO: GLint(pipRenderFBO))

        // Unbind FBO
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }

    /// Set up offscreen FBO for PiP rendering.
    private func setupPiPRenderFBO(width: Int, height: Int) {
        // Skip if dimensions unchanged and FBO exists
        if width == pipRenderWidth && height == pipRenderHeight && pipRenderFBO != 0 {
            return
        }

        // Clean up existing FBO
        if pipRenderFBO != 0 {
            glDeleteFramebuffers(1, &pipRenderFBO)
            pipRenderFBO = 0
        }
        if pipRenderTexture != 0 {
            glDeleteTextures(1, &pipRenderTexture)
            pipRenderTexture = 0
        }

        pipRenderWidth = width
        pipRenderHeight = height

        // Create render texture
        glGenTextures(1, &pipRenderTexture)
        glBindTexture(GLenum(GL_TEXTURE_2D), pipRenderTexture)
        glTexImage2D(
            GLenum(GL_TEXTURE_2D),
            0,
            GL_RGBA8,
            GLsizei(width),
            GLsizei(height),
            0,
            GLenum(GL_RGBA),
            GLenum(GL_UNSIGNED_BYTE),
            nil
        )
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)

        // Create FBO and attach texture
        glGenFramebuffers(1, &pipRenderFBO)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), pipRenderFBO)
        glFramebufferTexture2D(
            GLenum(GL_FRAMEBUFFER),
            GLenum(GL_COLOR_ATTACHMENT0),
            GLenum(GL_TEXTURE_2D),
            pipRenderTexture,
            0
        )

        // Check FBO status
        let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if status != GL_FRAMEBUFFER_COMPLETE {
            Task { @MainActor in
                LoggingService.shared.warning("MPVOpenGLLayer: PiP render FBO incomplete: \(status)", category: .mpv)
            }
        }

        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)

        Task { @MainActor in
            LoggingService.shared.debug("MPVOpenGLLayer: Created PiP render FBO \(width)x\(height)", category: .mpv)
        }
    }

    /// Clear the layer to black.
    func clearToBlack() {
        renderQueue.async { [weak self] in
            guard let self else { return }

            CGLSetCurrentContext(self.cglContext)
            glClearColor(0.0, 0.0, 0.0, 1.0)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            glFlush()

            // Force a display to show the cleared frame
            self.update(force: true)
        }
    }

    /// Reset first frame tracking (call when loading new content).
    func resetFirstFrameTracking() {
        hasRenderedFirstFrame = false
    }

    // MARK: - Pixel Format and Context Creation

    /// Create a CGL pixel format, trying 10-bit first, falling back to 8-bit.
    private static func createPixelFormat() -> (CGLPixelFormatObj, GLint) {
        var pixelFormat: CGLPixelFormatObj?
        var numPixelFormats: GLint = 0

        // Try 10-bit first
        var result = CGLChoosePixelFormat(glFormat10Bit, &pixelFormat, &numPixelFormats)
        if result == kCGLNoError, let pf = pixelFormat {
            Task { @MainActor in
                LoggingService.shared.debug("MPVOpenGLLayer: created 10-bit pixel format", category: .mpv)
            }
            return (pf, 16)
        }

        // Fall back to 8-bit
        result = CGLChoosePixelFormat(glFormatBase, &pixelFormat, &numPixelFormats)
        if result == kCGLNoError, let pf = pixelFormat {
            Task { @MainActor in
                LoggingService.shared.debug("MPVOpenGLLayer: created 8-bit pixel format", category: .mpv)
            }
            return (pf, 8)
        }

        // This should not happen on any reasonable Mac
        fatalError("MPVOpenGLLayer: failed to create any OpenGL pixel format")
    }

    /// Create a CGL context with the given pixel format.
    private static func createContext(pixelFormat: CGLPixelFormatObj) -> CGLContextObj {
        var context: CGLContextObj?
        let result = CGLCreateContext(pixelFormat, nil, &context)

        guard result == kCGLNoError, let ctx = context else {
            fatalError("MPVOpenGLLayer: failed to create OpenGL context: \(result)")
        }

        // Enable vsync
        var swapInterval: GLint = 1
        CGLSetParameter(ctx, kCGLCPSwapInterval, &swapInterval)

        // Enable multi-threaded OpenGL engine for better performance
        CGLEnable(ctx, kCGLCEMPEngine)

        CGLSetCurrentContext(ctx)

        Task { @MainActor in
            LoggingService.shared.debug("MPVOpenGLLayer: created CGL context with vsync and multi-threaded engine", category: .mpv)
        }

        return ctx
    }

    // MARK: - PiP Capture Methods

    /// Update the cached time position for PiP presentation timestamps.
    func updateTimePosition(_ time: Double) {
        cachedTimePos = time
    }

    /// Update the target PiP capture size and force recreation of capture resources.
    /// Called when PiP window size changes (via didTransitionToRenderSize).
    func updatePiPTargetSize(_ size: CMVideoDimensions) {
        // Force recreation of capture resources at new size by resetting dimensions
        pipCaptureWidth = 0
        pipCaptureHeight = 0
        Task { @MainActor in
            LoggingService.shared.debug("MPVOpenGLLayer: Updated PiP target size to \(size.width)x\(size.height)", category: .mpv)
        }
    }

    /// Set up the texture cache and PiP framebuffer for zero-copy capture.
    private func setupPiPCapture(width: Int, height: Int) {
        // Skip if dimensions unchanged and resources exist
        if width == pipCaptureWidth && height == pipCaptureHeight && textureCache != nil {
            return
        }

        // Clean up existing resources
        destroyPiPCapture()

        pipCaptureWidth = width
        pipCaptureHeight = height

        // Create texture cache with our CGL context and pixel format
        var cache: CVOpenGLTextureCache?
        let cacheResult = CVOpenGLTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            cglContext,
            cglPixelFormat,
            nil,
            &cache
        )
        guard cacheResult == kCVReturnSuccess, let cache else {
            Task { @MainActor in
                LoggingService.shared.warning("MPVOpenGLLayer PiP: Failed to create texture cache: \(cacheResult)", category: .mpv)
            }
            return
        }
        textureCache = cache

        // Create pixel buffer with IOSurface backing for zero-copy
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            kCVPixelBufferOpenGLCompatibilityKey as String: true
        ]

        var pixelBuffer: CVPixelBuffer?
        let pbResult = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            pixelBufferAttributes as CFDictionary,
            &pixelBuffer
        )
        guard pbResult == kCVReturnSuccess, let pixelBuffer else {
            Task { @MainActor in
                LoggingService.shared.warning("MPVOpenGLLayer PiP: Failed to create pixel buffer: \(pbResult)", category: .mpv)
            }
            return
        }
        pipPixelBuffer = pixelBuffer

        // Create GL texture from pixel buffer via texture cache
        var texture: CVOpenGLTexture?
        let texResult = CVOpenGLTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            &texture
        )
        guard texResult == kCVReturnSuccess, let texture else {
            Task { @MainActor in
                LoggingService.shared.warning("MPVOpenGLLayer PiP: Failed to create texture from pixel buffer: \(texResult)", category: .mpv)
            }
            return
        }
        pipTexture = texture

        // Get texture properties (macOS typically uses GL_TEXTURE_RECTANGLE_ARB)
        let textureTarget = CVOpenGLTextureGetTarget(texture)
        let textureName = CVOpenGLTextureGetName(texture)

        // Create FBO for PiP capture
        glGenFramebuffers(1, &pipFramebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), pipFramebuffer)

        // Attach texture to FBO
        glFramebufferTexture2D(
            GLenum(GL_FRAMEBUFFER),
            GLenum(GL_COLOR_ATTACHMENT0),
            textureTarget,
            textureName,
            0
        )

        // Verify FBO is complete
        let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if status != GL_FRAMEBUFFER_COMPLETE {
            Task { @MainActor in
                LoggingService.shared.warning("MPVOpenGLLayer PiP: Framebuffer incomplete: \(status)", category: .mpv)
            }
            destroyPiPCapture()
            return
        }

        // Restore default framebuffer
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)

        Task { @MainActor in
            LoggingService.shared.debug("MPVOpenGLLayer PiP: Zero-copy capture setup complete (\(width)x\(height)), textureTarget=\(textureTarget)", category: .mpv)
        }
    }

    /// Clean up PiP capture resources.
    private func destroyPiPCapture() {
        if pipFramebuffer != 0 {
            glDeleteFramebuffers(1, &pipFramebuffer)
            pipFramebuffer = 0
        }
        if pipRenderFBO != 0 {
            glDeleteFramebuffers(1, &pipRenderFBO)
            pipRenderFBO = 0
        }
        if pipRenderTexture != 0 {
            glDeleteTextures(1, &pipRenderTexture)
            pipRenderTexture = 0
        }
        pipTexture = nil
        pipPixelBuffer = nil
        if let cache = textureCache {
            CVOpenGLTextureCacheFlush(cache, 0)
        }
        textureCache = nil
        pipCaptureWidth = 0
        pipCaptureHeight = 0
        pipRenderWidth = 0
        pipRenderHeight = 0
    }

    /// Capture the current framebuffer contents as a CVPixelBuffer for PiP (zero-copy).
    private func captureFrameForPiP(viewWidth: GLint, viewHeight: GLint, mainFBO: GLint) {
        guard viewWidth > 0, viewHeight > 0, let callback = onFrameReady else { return }

        // Use actual video dimensions for capture (avoid capturing letterbox/pillarbox black bars)
        // If video dimensions not set, fall back to view dimensions
        let captureVideoWidth = videoContentWidth > 0 ? videoContentWidth : Int(viewWidth)
        let captureVideoHeight = videoContentHeight > 0 ? videoContentHeight : Int(viewHeight)

        // Set up or update capture resources if needed (based on video dimensions)
        setupPiPCapture(width: captureVideoWidth, height: captureVideoHeight)

        guard pipFramebuffer != 0, let pixelBuffer = pipPixelBuffer else { return }

        // Calculate the source rect in the framebuffer that contains just the video
        // (excluding letterbox/pillarbox black bars)
        let videoAspect = CGFloat(captureVideoWidth) / CGFloat(captureVideoHeight)
        let viewAspect = CGFloat(viewWidth) / CGFloat(viewHeight)

        var srcX: GLint = 0
        var srcY: GLint = 0
        var srcWidth = viewWidth
        var srcHeight = viewHeight

        if videoAspect > viewAspect {
            // Video is wider than view - pillarboxed (black bars on top/bottom)
            let scaledHeight = CGFloat(viewWidth) / videoAspect
            srcY = GLint((CGFloat(viewHeight) - scaledHeight) / 2)
            srcHeight = GLint(scaledHeight)
        } else if videoAspect < viewAspect {
            // Video is taller than view - letterboxed (black bars on left/right)
            let scaledWidth = CGFloat(viewHeight) * videoAspect
            srcX = GLint((CGFloat(viewWidth) - scaledWidth) / 2)
            srcWidth = GLint(scaledWidth)
        }

        // Bind PiP framebuffer as draw target
        glBindFramebuffer(GLenum(GL_DRAW_FRAMEBUFFER), pipFramebuffer)
        glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), GLenum(mainFBO))

        // Blit from main framebuffer to PiP framebuffer (with scaling and vertical flip)
        // Source: just the video area in main framebuffer (bottom-left origin)
        // Dest: PiP texture (top-left origin, so we flip Y)
        glBlitFramebuffer(
            srcX, srcY, srcX + srcWidth, srcY + srcHeight,           // src rect (video area only)
            0, GLint(pipCaptureHeight), GLint(pipCaptureWidth), 0,   // dst rect (flipped Y)
            GLbitfield(GL_COLOR_BUFFER_BIT),
            GLenum(GL_LINEAR)
        )

        // Restore main framebuffer
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), GLenum(mainFBO))

        // Flush to ensure texture is updated before passing to AVSampleBufferDisplayLayer
        glFlush()

        // Create presentation time from cached time position
        let presentationTime = CMTime(seconds: cachedTimePos, preferredTimescale: 90000)

        // Log periodically
        pipFrameCount += 1
        if pipFrameCount <= 3 || pipFrameCount % 120 == 0 {
            // Capture values to avoid capturing self in @Sendable closure
            let frameCount = pipFrameCount
            let timePos = cachedTimePos
            Task { @MainActor in
                LoggingService.shared.debug("MPVOpenGLLayer PiP: Captured frame #\(frameCount), \(captureVideoWidth)x\(captureVideoHeight), time=\(timePos)", category: .mpv)
            }
        }

        // Deliver the frame - pixel buffer is already populated via zero-copy
        DispatchQueue.main.async {
            callback(pixelBuffer, presentationTime)
        }
    }
}

// MARK: - OpenGL Proc Address

/// Get OpenGL function address for macOS.
private func macOSGetProcAddress(
    _ ctx: UnsafeMutableRawPointer?,
    _ name: UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    let symbolName = String(cString: name)

    guard let framework = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString) else {
        return nil
    }

    return CFBundleGetFunctionPointerForName(framework, symbolName as CFString)
}

#endif
