import Foundation
import SwiftUI

struct FixtureEnvironmentObjectsModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environmentObject(InstancesModel())
            .environmentObject(api)
            .environmentObject(NavigationModel())
            .environmentObject(PlaybackModel())
            .environmentObject(PlaylistsModel())
            .environmentObject(RecentsModel())
            .environmentObject(SearchModel())
            .environmentObject(SubscriptionsModel(api: api))
    }

    private var api: InvidiousAPI {
        let api = InvidiousAPI()

        api.validInstance = true
        api.signedIn = true

        return api
    }
}

extension View {
    func injectFixtureEnvironmentObjects() -> some View {
        modifier(FixtureEnvironmentObjectsModifier())
    }
}
