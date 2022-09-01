import Combine
import SwiftUI

struct TVControls: UIViewRepresentable {
    var model: PlayerControlsModel!
    var player: PlayerModel!
    var thumbnails: ThumbnailsModel!

    @State private var direction = ""
    @State private var controlsArea = UIView()

    func makeUIView(context: Context) -> UIView {
        let leftSwipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(sender:)))
        leftSwipe.direction = .left

        let rightSwipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(sender:)))
        rightSwipe.direction = .right

        let upSwipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(sender:)))
        upSwipe.direction = .up

        let downSwipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeDown(sender:)))
        downSwipe.direction = .down

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(sender:)))

        controlsArea.addGestureRecognizer(leftSwipe)
        controlsArea.addGestureRecognizer(rightSwipe)
        controlsArea.addGestureRecognizer(upSwipe)
        controlsArea.addGestureRecognizer(downSwipe)
        controlsArea.addGestureRecognizer(tap)

        let controls = UIHostingController(rootView: PlayerControls(player: player, thumbnails: thumbnails))
        controls.view.frame = .init(
            origin: .init(x: SafeArea.insets.left, y: SafeArea.insets.top),
            size: .init(
                width: UIScreen.main.bounds.width - SafeArea.horizontalInsets,
                height: UIScreen.main.bounds.height - SafeArea.verticalInset
            )
        )

        controlsArea.addSubview(controls.view)

        return controlsArea
    }

    func updateUIView(_: UIView, context _: Context) {}

    func makeCoordinator() -> TVControls.Coordinator {
        Coordinator(controlsArea)
    }

    final class Coordinator: NSObject {
        private let view: UIView
        private let model: PlayerControlsModel

        init(_ view: UIView) {
            self.view = view
            model = .shared
            super.init()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        @objc func handleSwipe(sender: UISwipeGestureRecognizer) {
            let location = sender.location(in: view)
            model.reporter.send("swipe \(location)")
        }

        @objc func handleSwipeDown(sender _: UISwipeGestureRecognizer) {
            model.reporter.send("swipe down")
        }

        @objc func handleTap(sender _: UITapGestureRecognizer) {
            if !model.presentingControls {
                model.show()
            }
        }
    }
}
