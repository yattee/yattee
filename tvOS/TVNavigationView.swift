import Defaults
import SwiftUI

struct TVNavigationView: View {
    @EnvironmentObject<NavigationState> private var navigationState
    @EnvironmentObject<PlaybackState> private var playbackState
    @EnvironmentObject<Recents> private var recents
    @EnvironmentObject<SearchState> private var searchState

    @State private var showingOptions = false

    @Default(.showingAddToPlaylist) var showingAddToPlaylist

    var body: some View {
        TabView(selection: $navigationState.tabSelection) {
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
                .searchable(text: $searchState.queryText) {
                    ForEach(searchState.querySuggestions.collection, id: \.self) { suggestion in
                        Text(suggestion)
                            .searchCompletion(suggestion)
                    }
                }
                .onChange(of: searchState.queryText) { newQuery in
                    searchState.loadQuerySuggestions(newQuery)
                    searchState.changeQuery { query in query.query = newQuery }
                }
                .tabItem { Image(systemName: "magnifyingglass") }
                .tag(TabSelection.search)
        }
        .fullScreenCover(isPresented: $showingOptions) { OptionsView() }
        .fullScreenCover(isPresented: $showingAddToPlaylist) { AddToPlaylistView() }
        .fullScreenCover(isPresented: $navigationState.showingVideo) {
            if let video = navigationState.video {
                VideoPlayerView(video)
                    .environmentObject(playbackState)
            }
        }
        .fullScreenCover(isPresented: $navigationState.isChannelOpen) {
            if let channel = recents.presentedChannel {
                ChannelVideosView(channel)
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
