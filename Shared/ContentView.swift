import Defaults
import SwiftUI

struct ContentView: View {
    @ObservedObject private var state = AppState()
    @ObservedObject private var profile = Profile()

    @Default(.tabSelection) var tabSelection

    var body: some View {
        NavigationView {
            TabView(selection: $tabSelection) {
                SubscriptionsView()
                    .tabItem { Text("Subscriptions") }
                    .tag(TabSelection.subscriptions)

                PopularVideosView()
                    .tabItem { Text("Popular") }
                    .tag(TabSelection.popular)

                if state.showingChannel {
                    ChannelView()
                        .tabItem { Text("\(state.channel) Channel") }
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
        }
        .environmentObject(state)
        .environmentObject(profile)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
