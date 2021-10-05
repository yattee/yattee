import Defaults
import SwiftUI

struct Player: UIViewControllerRepresentable {
    @EnvironmentObject<InvidiousAPI> private var api
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

        player.controller = controller
        controller.playerModel = player
        controller.api = api

        controller.resolution = Defaults[.quality]

        return controller
    }

    func updateUIViewController(_: PlayerViewController, context _: Context) {}
}
