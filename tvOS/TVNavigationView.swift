import Defaults
import SwiftUI

struct TVNavigationView: View {
    @EnvironmentObject<NavigationState> private var navigationState

    @State private var showingOptions = false

    @Default(.showingAddToPlaylist) var showingAddToPlaylist

    var body: some View {
        TabView(selection: $navigationState.tabSelection) {
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
        .fullScreenCover(isPresented: $showingOptions) { OptionsView() }
        .fullScreenCover(isPresented: $showingAddToPlaylist) { AddToPlaylistView() }
        .fullScreenCover(isPresented: $navigationState.showingVideoDetails) {
            if let video = navigationState.video {
                VideoDetailsView(video)
            }
        }
        .fullScreenCover(isPresented: $navigationState.showingChannel, onDismiss: {
            navigationState.showVideoDetailsIfNeeded()
        }) {
            if let channel = navigationState.channel {
                ChannelView(id: channel.id)
            }
        }
        .fullScreenCover(isPresented: $navigationState.showingVideo) {
            if let video = navigationState.video {
                VideoPlayerView(video)
            }
        }
        .onPlayPauseCommand { showingOptions.toggle() }
    }
}

struct TVNavigationView_Previews: PreviewProvider {
    static var previews: some View {
        TVNavigationView()
    }
}
