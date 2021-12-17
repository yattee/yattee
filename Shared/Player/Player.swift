import Defaults
import SwiftUI

struct Player: UIViewControllerRepresentable {
    @EnvironmentObject<CommentsModel> private var comments
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    var controller: PlayerViewController?

    init(controller: PlayerViewController? = nil) {
        self.controller = controller
    }

    func makeUIViewController(context _: Context) -> PlayerViewController {
        if self.controller != nil {
            return self.controller!
        }

        let controller = PlayerViewController()

        controller.commentsModel = comments
        controller.navigationModel = navigation
        controller.playerModel = player
        controller.subscriptionsModel = subscriptions
        player.controller = controller

        return controller
    }

    func updateUIViewController(_: PlayerViewController, context _: Context) {
        player.rebuildTVMenu()
    }
}
