import Foundation
import SwiftUI

struct FixtureEnvironmentObjectsModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environmentObject(AccountsModel())
            .environmentObject(comments)
            .environmentObject(InstancesModel())
            .environmentObject(invidious)
            .environmentObject(NavigationModel())
            .environmentObject(NetworkStateModel())
            .environmentObject(PipedAPI())
            .environmentObject(player)
            .environmentObject(playerControls)
            .environmentObject(PlayerTimeModel())
            .environmentObject(PlaylistsModel())
            .environmentObject(RecentsModel())
            .environmentObject(SearchModel())
            .environmentObject(subscriptions)
            .environmentObject(ThumbnailsModel())
    }

    private var comments: CommentsModel {
        let comments = CommentsModel()
        comments.loaded = true
        comments.all = [.fixture]

        return comments
    }

    private var invidious: InvidiousAPI {
        let api = InvidiousAPI()

        api.validInstance = true
        api.signedIn = true

        return api
    }

    private var player: PlayerModel {
        let player = PlayerModel()

        player.currentItem = PlayerQueueItem(Video.fixture)
        player.queue = Video.allFixtures.map { PlayerQueueItem($0) }

        return player
    }

    private var playerControls: PlayerControlsModel {
        PlayerControlsModel(presentingControls: true, player: player)
    }

    private var subscriptions: SubscriptionsModel {
        let subscriptions = SubscriptionsModel()

        subscriptions.channels = Video.allFixtures.map { $0.channel }

        return subscriptions
    }
}

extension View {
    func injectFixtureEnvironmentObjects() -> some View {
        modifier(FixtureEnvironmentObjectsModifier())
    }
}
