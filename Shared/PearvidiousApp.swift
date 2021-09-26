import Defaults
import SwiftUI

@main
struct PearvidiousApp: App {
    @StateObject private var api = InvidiousAPI()
    @StateObject private var instances = InstancesModel()
    @StateObject private var playlists = PlaylistsModel()
    @StateObject private var search = SearchModel()
    @StateObject private var subscriptions = SubscriptionsModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear(perform: configureAPI)
                .environmentObject(api)
                .environmentObject(instances)
                .environmentObject(playlists)
                .environmentObject(search)
                .environmentObject(subscriptions)
        }
        #if !os(tvOS)
            .commands {
                SidebarCommands()
            }
        #endif

        #if os(macOS)
            Settings {
                SettingsView()
                    .onAppear(perform: configureAPI)
                    .environmentObject(api)
                    .environmentObject(instances)
            }
        #endif
    }

    fileprivate func configureAPI() {
        playlists.api = api
        search.api = api
        subscriptions.api = api

        guard api.account.isNil, instances.defaultAccount != nil else {
            return
        }

        api.setAccount(instances.defaultAccount)
    }
}
