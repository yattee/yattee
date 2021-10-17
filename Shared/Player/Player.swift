import Defaults
import SwiftUI

struct Player: UIViewControllerRepresentable {
    @EnvironmentObject<PlayerModel> private var player

    var controller: PlayerViewController?

    init(controller: PlayerViewController? = nil) {
        self.controller = controller
    }

    func makeUIViewController(context _: Context) -> PlayerViewController {
        if self.controller != nil {
            return self.controller!
        }

        let controller = PlayerViewController()

        controller.playerModel = player
        player.controller = controller

        #if os(tvOS)
            player.controller?.playerViewController.transportBarCustomMenuItems = [streamingQualityMenu]
        #endif

        return controller
    }

    func updateUIViewController(_: PlayerViewController, context _: Context) {
        #if os(tvOS)
            player.controller?.playerViewController.transportBarCustomMenuItems = [streamingQualityMenu]
        #endif
    }

    #if os(tvOS)
        var streamingQualityMenu: UIMenu {
            UIMenu(
                title: "Streams",
                image: UIImage(systemName: "antenna.radiowaves.left.and.right"),
                children: streamingQualityMenuActions
            )
        }

        var streamingQualityMenuActions: [UIAction] {
            guard !player.availableStreams.isEmpty else {
                return [ // swiftlint:disable:this implicit_return
                    UIAction(title: "Empty", attributes: .disabled) { _ in }
                ]
            }

            return player.availableStreamsSorted.map { stream in
                let state = player.streamSelection == stream ? UIAction.State.on : .off

                return UIAction(title: stream.description, state: state) { _ in
                    self.player.streamSelection = stream
                    self.player.upgradeToStream(stream)
                }
            }
        }
    #endif
}
