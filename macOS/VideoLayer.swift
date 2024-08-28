import Cocoa
import Libmpv
import OpenGL.GL
import OpenGL.GL3

final class VideoLayer: CAOpenGLLayer {
    var client: MPVClient!

    override init() {
        super.init()
        autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backgroundColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func canDraw(
        inCGLContext _: CGLContextObj,
        pixelFormat _: CGLPixelFormatObj,
        forLayerTime _: CFTimeInterval,
        displayTime _: UnsafePointer<CVTimeStamp>?
    ) -> Bool {
        true
    }

    override func draw(
        inCGLContext ctx: CGLContextObj,
        pixelFormat _: CGLPixelFormatObj,
        forLayerTime _: CFTimeInterval,
        displayTime _: UnsafePointer<CVTimeStamp>?
    ) {
        var i: GLint = 0
        var flip: CInt = 1
        var ditherDepth = 8
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &i)

        if client.mpvGL != nil {
            var data = mpv_opengl_fbo(
                fbo: Int32(i),
                w: Int32(bounds.size.width),
                h: Int32(bounds.size.height),
                internal_format: 0
            )
            var params: [mpv_render_param] = [
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: &data),
                mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: &flip),
                mpv_render_param(type: MPV_RENDER_PARAM_DEPTH, data: &ditherDepth),
                mpv_render_param()
            ]
            mpv_render_context_render(client.mpvGL, &params)
        } else {
            glClearColor(0, 0, 0, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))
        }

        CGLFlushDrawable(ctx)
    }

    override func copyCGLPixelFormat(forDisplayMask _: UInt32) -> CGLPixelFormatObj {
        let attrs: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
            kCGLPFADoubleBuffer,
            kCGLPFAAllowOfflineRenderers,
            kCGLPFABackingStore,
            kCGLPFAAccelerated,
            kCGLPFASupportsAutomaticGraphicsSwitching,
            _CGLPixelFormatAttribute(rawValue: 0)
        ]

        var npix: GLint = 0
        var pix: CGLPixelFormatObj?
        CGLChoosePixelFormat(attrs, &pix, &npix)

        return pix!
    }

    override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj {
        let ctx = super.copyCGLContext(forPixelFormat: pf)

        var i: GLint = 1
        CGLSetParameter(ctx, kCGLCPSwapInterval, &i)
        CGLEnable(ctx, kCGLCEMPEngine)
        CGLSetCurrentContext(ctx)

        client.create()
        initDisplayLink()

        return ctx
    }

    override func display() {
        super.display()
        CATransaction.flush()
    }

    let displayLinkCallback: CVDisplayLinkOutputCallback = { _, _, _, _, _, displayLinkContext -> CVReturn in
        let layer: VideoLayer = unsafeBitCast(displayLinkContext, to: VideoLayer.self)
        if layer.client?.mpvGL != nil {
            mpv_render_context_report_swap(layer.client.mpvGL)
        }
        return kCVReturnSuccess
    }

    func initDisplayLink() {
        let displayId = UInt32(NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! Int)

        CVDisplayLinkCreateWithCGDisplay(displayId, &client.link)
        CVDisplayLinkSetOutputCallback(
            client.link!, displayLinkCallback,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(client.layer).toOpaque())
        )
        CVDisplayLinkStart(client.link!)
    }

    func uninitDisplaylink() {
        if CVDisplayLinkIsRunning(client.link!) {
            CVDisplayLinkStop(client.link!)
        }
    }
}
