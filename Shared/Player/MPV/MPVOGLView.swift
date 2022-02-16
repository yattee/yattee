import GLKit
import OpenGLES

final class MPVOGLView: GLKView {
    private var defaultFBO: GLint?

    var mpvGL: UnsafeMutableRawPointer?
    var needsDrawing = true

    override init(frame: CGRect) {
        guard let context = EAGLContext(api: .openGLES2) else {
            print("Failed to initialize OpenGLES 2.0 context")
            exit(1)
        }

        super.init(frame: frame, context: context)
        contentMode = .redraw

        EAGLContext.setCurrent(context)

        drawableColorFormat = .RGBA8888
        drawableDepthFormat = .formatNone
        drawableStencilFormat = .formatNone

        defaultFBO = -1
        isOpaque = false

        fillBlack()
    }

    func fillBlack() {
        glClearColor(0, 0, 0, 0)
        glClear(UInt32(GL_COLOR_BUFFER_BIT))
    }

    override func draw(_: CGRect) {
        glGetIntegerv(UInt32(GL_FRAMEBUFFER_BINDING), &defaultFBO!)

        if mpvGL != nil {
            var data = mpv_opengl_fbo(
                fbo: Int32(defaultFBO!),
                w: Int32(bounds.size.width) * Int32(contentScaleFactor),
                h: Int32(bounds.size.height) * Int32(contentScaleFactor),
                internal_format: 0
            )
            var flip: CInt = 1
            withUnsafeMutablePointer(to: &flip) { flip in
                withUnsafeMutablePointer(to: &data) { data in
                    var params = [
                        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: data),
                        mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flip),
                        mpv_render_param()
                    ]
                    mpv_render_context_render(OpaquePointer(mpvGL), &params)
                }
            }
        }
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}
