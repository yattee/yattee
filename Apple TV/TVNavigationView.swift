import Defaults
import SwiftUI

struct TVNavigationView: View {
    @EnvironmentObject<NavigationState> private var navigationState

    @State private var showingOptions = false

    var body: some View {
        NavigationView {
            TabView(selection: $navigationState.tabSelection) {
                SubscriptionsView()
                    .tabItem { Text("Subscriptions") }
                    .tag(TabSelection.subscriptions)

                PopularVideosView()
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
            .fullScreenCover(isPresented: $navigationState.showingVideoDetails) {
                if let video = navigationState.video {
                    VideoDetailsView(video)
                }
            }
            .fullScreenCover(isPresented: $navigationState.showingChannel) {
                if let channel = navigationState.channel {
                    ChannelView(id: channel.id)
                }
            }

            .onPlayPauseCommand { showingOptions.toggle() }
        }
    }
}

struct TVNavigationView_Previews: PreviewProvider {
    static var previews: some View {
        TVNavigationView()
    }
}
