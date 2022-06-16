import GLKit
import Logging
import OpenGLES

final class MPVOGLView: GLKView {
    private var logger = Logger(label: "stream.yattee.mpv.oglview")
    private var defaultFBO: GLint?

    var mpvGL: UnsafeMutableRawPointer?
    var queue = DispatchQueue(label: "stream.yattee.opengl", qos: .userInteractive)
    var needsDrawing = true

    override init(frame: CGRect) {
        guard let context = EAGLContext(api: .openGLES3) else {
            print("Failed to initialize OpenGLES 2.0 context")
            exit(1)
        }

        logger.info("frame size: \(frame.width) x \(frame.height)")

        super.init(frame: frame, context: context)

        EAGLContext.setCurrent(context)

        defaultFBO = -1
        isOpaque = false

        fillBlack()
    }

    func fillBlack() {
        glClearColor(0, 0, 0, 0)
        glClear(UInt32(GL_COLOR_BUFFER_BIT))
    }

    override func draw(_: CGRect) {
        guard needsDrawing, let mpvGL = mpvGL else {
            return
        }

        glGetIntegerv(UInt32(GL_FRAMEBUFFER_BINDING), &defaultFBO!)

        var dims: [GLint] = [0, 0, 0, 0]
        glGetIntegerv(GLenum(GL_VIEWPORT), &dims)

        var data = mpv_opengl_fbo(
            fbo: Int32(defaultFBO!),
            w: Int32(dims[2]),
            h: Int32(dims[3]),
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

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}
