import Defaults
import SwiftUI

struct TVNavigationView: View {
    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SettingsModel> private var settings

    @Default(.visibleSections) private var visibleSections

    @State private var playerInitialized = false

    var body: some View {
        NavigationView {
            TabView(selection: navigation.tabSelectionBinding) {
                if visibleSections.contains(.favorites) {
                    FavoritesView()
                        .tabItem { Text("Favorites") }
                        .tag(TabSelection.favorites)
                }

                if visibleSections.contains(.subscriptions), accounts.app.supportsSubscriptions, accounts.api.signedIn {
                    SubscriptionsView()
                        .tabItem { Text("Subscriptions") }
                        .tag(TabSelection.subscriptions)
                }

                if visibleSections.contains(.popular), accounts.app.supportsPopular {
                    PopularView()
                        .tabItem { Text("Popular") }
                        .tag(TabSelection.popular)
                }

                if visibleSections.contains(.trending) {
                    TrendingView()
                        .tabItem { Text("Trending") }
                        .tag(TabSelection.trending)
                }

                if visibleSections.contains(.playlists), accounts.app.supportsUserPlaylists, accounts.signedIn {
                    PlaylistsView()
                        .tabItem { Text("Playlists") }
                        .tag(TabSelection.playlists)
                }

                NowPlayingView()
                    .tabItem { Text("Now Playing") }
                    .tag(TabSelection.nowPlaying)

                SearchView()
                    .tabItem { Image(systemName: "magnifyingglass") }
                    .tag(TabSelection.search)

                SettingsView()
                    .tabItem { Image(systemName: "gear") }
                    .tag(TabSelection.settings)
            }
        }
        .background(videoPlayerInitialize)
        .fullScreenCover(isPresented: $navigation.presentingAddToPlaylist) {
            if let video = navigation.videoToAddToPlaylist {
                AddToPlaylistView(video: video)
            }
        }
        .fullScreenCover(isPresented: $player.presentingPlayer) {
            VideoPlayerView()
        }
        .fullScreenCover(isPresented: $navigation.presentingChannel) {
            if let channel = recents.presentedChannel {
                ChannelVideosView(channel: channel)
            }
        }
        .fullScreenCover(isPresented: $navigation.presentingPlaylist) {
            if let playlist = recents.presentedPlaylist {
                ChannelPlaylistView(playlist: playlist)
            }
        }
    }

    @ViewBuilder var videoPlayerInitialize: some View {
        if !playerInitialized {
            VideoPlayerView()
                .scaleEffect(0.00001)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        playerInitialized = true
                    }
                }
        }
    }
}

struct TVNavigationView_Previews: PreviewProvider {
    static var previews: some View {
        TVNavigationView()
            .injectFixtureEnvironmentObjects()
    }
}
