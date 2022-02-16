import Defaults
import SwiftUI

struct AVPlayerView: UIViewControllerRepresentable {
    @EnvironmentObject<CommentsModel> private var comments
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    func makeUIViewController(context _: Context) -> UIViewController {
        let controller = AppleAVPlayerViewController()

        controller.commentsModel = comments
        controller.navigationModel = navigation
        controller.playerModel = player
        controller.subscriptionsModel = subscriptions
        player.avPlayerBackend.controller = controller

        return controller
    }

    func updateUIViewController(_: UIViewController, context _: Context) {
        player.rebuildTVMenu()
    }
}
