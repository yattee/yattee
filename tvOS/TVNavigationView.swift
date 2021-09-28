import Defaults
import SwiftUI

struct TVNavigationView: View {
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlaybackModel> private var playback
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SearchModel> private var search

    var body: some View {
        TabView(selection: $navigation.tabSelection) {
            WatchNowView()
                .tabItem { Text("Watch Now") }
                .tag(TabSelection.watchNow)

            SubscriptionsView()
                .tabItem { Text("Subscriptions") }
                .tag(TabSelection.subscriptions)

            PopularView()
                .tabItem { Text("Popular") }
                .tag(TabSelection.popular)

            TrendingView()
                .tabItem { Text("Trending") }
                .tag(TabSelection.trending)

            PlaylistsView()
                .tabItem { Text("Playlists") }
                .tag(TabSelection.playlists)

            SearchView()
                .tabItem { Image(systemName: "magnifyingglass") }
                .tag(TabSelection.search)
        }
        .fullScreenCover(isPresented: $navigation.presentingSettings) { SettingsView() }
        .fullScreenCover(isPresented: $navigation.presentingAddToPlaylist) {
            if let video = navigation.videoToAddToPlaylist {
                AddToPlaylistView(video: video)
            }
        }
        .fullScreenCover(isPresented: $navigation.showingVideo) {
            if let video = navigation.video {
                VideoPlayerView(video)
                    .environmentObject(playback)
            }
        }
        .fullScreenCover(isPresented: $navigation.isChannelOpen) {
            if let channel = recents.presentedChannel {
                ChannelVideosView(channel: channel)
            }
        }
        .onPlayPauseCommand { navigation.presentingSettings.toggle() }
    }
}

struct TVNavigationView_Previews: PreviewProvider {
    static var previews: some View {
        TVNavigationView()
            .environmentObject(InvidiousAPI())
            .environmentObject(NavigationModel())
            .environmentObject(SearchModel())
            .environmentObject(InstancesModel())
            .environmentObject(SubscriptionsModel())
    }
}
