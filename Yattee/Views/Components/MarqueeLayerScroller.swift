//
//  MarqueeLayerScroller.swift
//  Yattee
//
//  Scrolls SwiftUI content with a Core Animation animation, which runs in
//  the render server: no body evaluations or app CPU per frame.
//

#if os(iOS) || os(tvOS)
import SwiftUI
import UIKit

/// Shows `content` at the leading edge, then repeatedly waits `delay`,
/// scrolls it left by `distance` over `scrollDuration` and jumps back.
/// The content is expected to repeat itself after `distance` so the jump
/// back is seamless.
struct MarqueeLayerScroller<Content: View>: UIViewRepresentable {
    let content: Content
    let contentWidth: CGFloat
    let distance: CGFloat
    let scrollDuration: Double
    let delay: Double
    let isPaused: Bool
    /// Restarts the cycle from the beginning when it changes (e.g. new text).
    let restartToken: String

    func makeUIView(context: Context) -> MarqueeLayerScrollerView<Content> {
        MarqueeLayerScrollerView(content: content)
    }

    func updateUIView(_ view: MarqueeLayerScrollerView<Content>, context: Context) {
        view.update(
            content: content,
            configuration: .init(
                contentWidth: contentWidth,
                distance: distance,
                scrollDuration: scrollDuration,
                delay: delay,
                restartToken: restartToken
            ),
            isPaused: isPaused
        )
    }
}

final class MarqueeLayerScrollerView<Content: View>: UIView {
    struct Configuration: Equatable {
        var contentWidth: CGFloat
        var distance: CGFloat
        var scrollDuration: Double
        var delay: Double
        var restartToken: String
    }

    private static var animationKey: String { "marquee" }

    private let hostingController: UIHostingController<Content>
    private var configuration: Configuration?
    private var isPaused = true

    init(content: Content) {
        hostingController = UIHostingController(rootView: content)
        // Laid out at a fixed frame; safe areas and size changes don't apply
        hostingController.safeAreaRegions = []
        hostingController.sizingOptions = []
        super.init(frame: .zero)
        clipsToBounds = true
        // Taps go to the SwiftUI view around the marquee (e.g. a Button label)
        isUserInteractionEnabled = false

        let hostView = hostingController.view!
        hostView.backgroundColor = .clear
        hostView.isUserInteractionEnabled = false
        addSubview(hostView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(content: Content, configuration newConfiguration: Configuration, isPaused newIsPaused: Bool) {
        hostingController.rootView = content

        let needsRestart = newConfiguration != configuration || newIsPaused != isPaused
        configuration = newConfiguration
        isPaused = newIsPaused
        setNeedsLayout()
        if needsRestart {
            restartAnimation()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let configuration else { return }
        hostingController.view.frame = CGRect(
            x: 0, y: 0,
            width: configuration.contentWidth,
            height: bounds.height
        )
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Core Animation drops animations of layers that leave the window
        restartAnimation()
    }

    private func restartAnimation() {
        let layer = hostingController.view.layer
        layer.removeAnimation(forKey: Self.animationKey)

        guard window != nil, !isPaused, let configuration,
              configuration.distance > 0, configuration.scrollDuration > 0 else { return }

        // Hold at the start for `delay`, then scroll linearly; repeating jumps
        // back to the start, where the second copy of the content was.
        let cycle = configuration.delay + configuration.scrollDuration
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, 0, -configuration.distance]
        animation.keyTimes = [0, NSNumber(value: configuration.delay / cycle), 1]
        animation.calculationMode = .linear
        animation.duration = cycle
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: Self.animationKey)
    }
}
#endif
