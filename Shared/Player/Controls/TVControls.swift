import Combine
import SwiftUI

struct TVControls: UIViewRepresentable {
    var model: PlayerControlsModel!
    var player: PlayerModel!
    var thumbnails: ThumbnailsModel!

    @State private var direction = ""
    @State private var controlsArea = UIView()

    func makeUIView(context: Context) -> UIView {
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(sender:)))

        let leftSwipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(sender:)))
        leftSwipe.direction = .left

        let rightSwipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(sender:)))
        rightSwipe.direction = .right

        let upSwipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(sender:)))
        upSwipe.direction = .up

        let downSwipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(sender:)))
        downSwipe.direction = .down

        controlsArea.addGestureRecognizer(tapGesture)
        controlsArea.addGestureRecognizer(leftSwipe)
        controlsArea.addGestureRecognizer(rightSwipe)
        controlsArea.addGestureRecognizer(upSwipe)
        controlsArea.addGestureRecognizer(downSwipe)

        let controls = UIHostingController(rootView: PlayerControls(player: player, thumbnails: thumbnails))
        controls.view.frame = .init(
            origin: .zero,
            size: .init(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        )

        controlsArea.addSubview(controls.view)

        return controlsArea
    }

    func updateUIView(_: UIView, context _: Context) {}

    func makeCoordinator() -> TVControls.Coordinator {
        Coordinator(controlsArea, model: model)
    }

    final class Coordinator: NSObject {
        private let view: UIView
        private let model: PlayerControlsModel

        init(_ view: UIView, model: PlayerControlsModel) {
            self.view = view
            self.model = model
            super.init()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        @objc func handleTap(sender: UITapGestureRecognizer) {
            let location = sender.location(in: view)
            model.reporter.send("tap \(location)")
            print("tap \(location)")
        }

        @objc func handleSwipe(sender: UISwipeGestureRecognizer) {
            let location = sender.location(in: view)
            model.reporter.send("swipe \(location)")
            print("swipe \(location)")
        }
    }
}
