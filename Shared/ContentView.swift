import SwiftUI

struct ContentView: View {
    @ObservedObject private var state = AppState()

    @SceneStorage("tabSelection") var tabSelection = TabSelection.subscriptions

    var body: some View {
        NavigationView {
            TabView(selection: $tabSelection) {
                SubscriptionsView(tabSelection: $tabSelection)
                    .tabItem { Text("Subscriptions") }
                    .tag(TabSelection.subscriptions)

                PopularVideosView(tabSelection: $tabSelection)
                    .tabItem { Text("Popular") }
                    .tag(TabSelection.popular)

                if state.showingChannel {
                    ChannelView(tabSelection: $tabSelection)
                        .tabItem { Text("\(state.channel) Channel") }
                        .tag(TabSelection.channel)
                }

                TrendingView(tabSelection: $tabSelection)
                    .tabItem { Text("Trending") }
                    .tag(TabSelection.trending)

                PlaylistsView(tabSelection: $tabSelection)
                    .tabItem { Text("Playlists") }
                    .tag(TabSelection.playlists)

                SearchView(tabSelection: $tabSelection)
                    .tabItem { Image(systemName: "magnifyingglass") }
                    .tag(TabSelection.search)
            }
        }
        .environmentObject(state)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
