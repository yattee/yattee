import Defaults
import SwiftUI

struct ContentView: View {
    @Default(.openChannel) var channel
    @StateObject private var profile = Profile()

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
            .environmentObject(profile)
        }
    }

    var tabSelection: Binding<TabSelection> {
        Binding(
            get: { Defaults[.tabSelection] },
            set: { Defaults[.tabSelection] = $0 }
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
