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
                title: "Streaming quality",
                image: UIImage(systemName: "antenna.radiowaves.left.and.right"),
                children: streamingQualityMenuActions
            )
        }

        var streamingQualityMenuActions: [UIAction] {
            player.availableStreamsSorted.map { stream in
                let image = player.streamSelection == stream ? UIImage(systemName: "checkmark") : nil

                return UIAction(title: stream.description, image: image) { _ in
                    self.player.streamSelection = stream
                    self.player.upgradeToStream(stream)
                }
            }
        }
    #endif
}
