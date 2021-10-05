import Foundation
import SwiftUI

struct FixtureEnvironmentObjectsModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environmentObject(InstancesModel())
            .environmentObject(api)
            .environmentObject(NavigationModel())
            .environmentObject(player)
            .environmentObject(PlaylistsModel())
            .environmentObject(RecentsModel())
            .environmentObject(SearchModel())
            .environmentObject(subscriptions)
    }

    private var api: InvidiousAPI {
        let api = InvidiousAPI()

        api.validInstance = true
        api.signedIn = true

        return api
    }

    private var player: PlayerModel {
        let player = PlayerModel()

        player.currentItem = PlayerQueueItem(Video.fixture)
        player.queue = Video.allFixtures.map { PlayerQueueItem($0) }
        player.history = player.queue

        return player
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
