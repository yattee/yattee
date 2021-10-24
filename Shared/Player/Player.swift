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

        return controller
    }

    func updateUIViewController(_: PlayerViewController, context _: Context) {
        player.rebuildTVMenu()
    }
}
