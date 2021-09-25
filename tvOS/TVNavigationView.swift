import Defaults
import SwiftUI

struct TVNavigationView: View {
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlaybackModel> private var playback
    @EnvironmentObject<Recents> private var recents
    @EnvironmentObject<SearchModel> private var search

    @State private var showingOptions = false

    @Default(.showingAddToPlaylist) var showingAddToPlaylist

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
                .searchable(text: $search.queryText) {
                    ForEach(search.querySuggestions.collection, id: \.self) { suggestion in
                        Text(suggestion)
                            .searchCompletion(suggestion)
                    }
                }
                .onChange(of: search.queryText) { newQuery in
                    search.loadSuggestions(newQuery)
                    search.changeQuery { query in query.query = newQuery }
                }
                .tabItem { Image(systemName: "magnifyingglass") }
                .tag(TabSelection.search)
        }
        .fullScreenCover(isPresented: $showingOptions) { OptionsView() }
        .fullScreenCover(isPresented: $showingAddToPlaylist) { AddToPlaylistView() }
        .fullScreenCover(isPresented: $navigation.showingVideo) {
            if let video = navigation.video {
                VideoPlayerView(video)
                    .environmentObject(playback)
            }
        }
        .fullScreenCover(isPresented: $navigation.isChannelOpen) {
            if let channel = recents.presentedChannel {
                ChannelVideosView(channel: channel)
                    .background(.thickMaterial)
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
