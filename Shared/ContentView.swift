import Defaults
import SwiftUI

struct ContentView: View {
    @Default(.openChannel) var channel
    @Default(.showingVideoDetails) var showDetails

    @State private var showingOptions = false

    var body: some View {
        NavigationView {
            TabView(selection: tabSelection) {
                SubscriptionsView()
                    .tabItem { Text("Subscriptions") }
                    .tag(TabSelection.subscriptions)

                PopularVideosView()
                    .tabItem { Text("Popular") }
                    .tag(TabSelection.popular)

                if channel != nil {
                    ChannelView(id: channel!.id)
                        .tabItem { Text("\(channel!.name) Channel") }
                        .tag(TabSelection.channel)
                }

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
            .onPlayPauseCommand { showingOptions.toggle() }
            .background(videoDetailsViewNavigationLink)
        }
    }

    var tabSelection: Binding<TabSelection> {
        Binding(
            get: { Defaults[.tabSelection] },
            set: { Defaults[.tabSelection] = $0 }
        )
    }

    var videoDetailsViewNavigationLink: some View {
        NavigationLink("", destination: VideoDetailsView(), isActive: $showDetails).hidden()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
