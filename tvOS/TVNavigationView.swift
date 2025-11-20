import Defaults
import SwiftUI

struct TVNavigationView: View {
    @ObservedObject private var accounts = AccountsModel.shared
    @ObservedObject private var navigation = NavigationModel.shared
    @ObservedObject private var player = PlayerModel.shared
    @ObservedObject private var recents = RecentsModel.shared

    @Default(.visibleSections) private var visibleSections

    var body: some View {
        NavigationView {
            TabView(selection: navigation.tabSelectionBinding) {
                LazyView(HomeView())
                    .tabItem { Text("Home") }
                    .tag(TabSelection.home)

                if !accounts.isEmpty {
                    if visibleSections.contains(.subscriptions), accounts.app.supportsSubscriptions, accounts.api.signedIn {
                        LazyView(SubscriptionsView())
                            .tabItem { Text("Subscriptions") }
                            .tag(TabSelection.subscriptions)
                    }

                    if visibleSections.contains(.popular), accounts.app.supportsPopular {
                        LazyView(PopularView())
                            .tabItem { Text("Popular") }
                            .tag(TabSelection.popular)
                    }

                    if FeatureFlags.trendingEnabled && visibleSections.contains(.trending) {
                        LazyView(TrendingView())
                            .tabItem { Text("Trending") }
                            .tag(TabSelection.trending)
                    }

                    if visibleSections.contains(.playlists), accounts.app.supportsUserPlaylists, accounts.signedIn {
                        LazyView(PlaylistsView())
                            .tabItem { Text("Playlists") }
                            .tag(TabSelection.playlists)
                    }
                }

                LazyView(NowPlayingView())
                    .tabItem { Text("Now Playing") }
                    .tag(TabSelection.nowPlaying)

                if !accounts.isEmpty {
                    LazyView(SearchView())
                        .tabItem { Image(systemName: "magnifyingglass") }
                        .tag(TabSelection.search)
                }
            }
        }
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
}

struct TVNavigationView_Previews: PreviewProvider {
    static var previews: some View {
        TVNavigationView()
            .injectFixtureEnvironmentObjects()
    }
}
