import AVKit
import Defaults
import SwiftUI

#if os(iOS)
    struct AppleAVPlayerView: UIViewRepresentable {
        @EnvironmentObject<PlayerModel> private var player

        func makeUIView(context _: Context) -> some UIView {
            let playerLayerView = PlayerLayerView(frame: .zero)
            playerLayerView.player = player
            return playerLayerView
        }

        func updateUIView(_: UIViewType, context _: Context) {}
    }
#else
    struct AppleAVPlayerView: UIViewControllerRepresentable {
        @EnvironmentObject<AccountsModel> private var accounts
        @EnvironmentObject<CommentsModel> private var comments
        @EnvironmentObject<NavigationModel> private var navigation
        @EnvironmentObject<PlayerModel> private var player
        @EnvironmentObject<PlaylistsModel> private var playlists
        @EnvironmentObject<SubscriptionsModel> private var subscriptions

        func makeUIViewController(context _: Context) -> AppleAVPlayerViewController {
            let controller = AppleAVPlayerViewController()

            controller.accountsModel = accounts
            controller.commentsModel = comments
            controller.navigationModel = navigation
            controller.playerModel = player
            controller.playlistsModel = playlists
            controller.subscriptionsModel = subscriptions

            player.avPlayerBackend.controller = controller

            return controller
        }

        func updateUIViewController(_: AppleAVPlayerViewController, context _: Context) {
            player.rebuildTVMenu()
        }
    }
#endif
