import Defaults
import SwiftUI

struct ContentView: View {
    @StateObject private var api = InvidiousAPI()
    @StateObject private var instances = InstancesModel()
    @StateObject private var navigation = NavigationModel()
    @StateObject private var player = PlayerModel()
    @StateObject private var playlists = PlaylistsModel()
    @StateObject private var recents = RecentsModel()
    @StateObject private var search = SearchModel()
    @StateObject private var subscriptions = SubscriptionsModel()

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        Section {
            #if os(iOS)
                if horizontalSizeClass == .compact {
                    AppTabNavigation()
                } else {
                    AppSidebarNavigation()
                }
            #elseif os(macOS)
                AppSidebarNavigation()
            #elseif os(tvOS)
                TVNavigationView()
            #endif
        }
        .onAppear(perform: configureAPI)
        .environmentObject(api)
        .environmentObject(instances)
        .environmentObject(navigation)
        .environmentObject(player)
        .environmentObject(playlists)
        .environmentObject(recents)
        .environmentObject(search)
        .environmentObject(subscriptions)
        #if os(iOS)
            .fullScreenCover(isPresented: $player.presentingPlayer) {
                VideoPlayerView()
                    .environmentObject(api)
                    .environmentObject(navigation)
                    .environmentObject(player)
                    .environmentObject(subscriptions)
            }
        #elseif os(macOS)
            .sheet(isPresented: $player.presentingPlayer) {
                VideoPlayerView()
                    .frame(minWidth: 900, minHeight: 800)
                    .environmentObject(api)
                    .environmentObject(navigation)
                    .environmentObject(player)
                    .environmentObject(subscriptions)
            }
        #endif
        #if !os(tvOS)
            .sheet(isPresented: $navigation.presentingAddToPlaylist) {
                AddToPlaylistView(video: navigation.videoToAddToPlaylist)
                    .environmentObject(api)
                    .environmentObject(playlists)
            }
            .sheet(isPresented: $navigation.presentingPlaylistForm) {
                PlaylistFormView(playlist: $navigation.editedPlaylist)
                    .environmentObject(api)
                    .environmentObject(playlists)
            }
            .sheet(isPresented: $navigation.presentingSettings) {
                SettingsView()
                    .environmentObject(api)
                    .environmentObject(instances)
            }
        #endif
    }

    func configureAPI() {
        if let account = instances.defaultAccount, api.account.isEmpty {
            api.setAccount(account)
        }

        player.api = api
        playlists.api = api
        search.api = api
        subscriptions.api = api
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .injectFixtureEnvironmentObjects()
    }
}
