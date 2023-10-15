import AppKit

final class MPVOGLView: NSView {
    override init(frame frameRect: CGRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        wantsBestResolutionOpenGLSurface = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
