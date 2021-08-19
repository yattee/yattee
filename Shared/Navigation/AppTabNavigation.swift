import Defaults
import SwiftUI

struct AppTabNavigation: View {
    @State private var tabSelection: TabSelection = .subscriptions

    var body: some View {
        TabView(selection: $tabSelection) {
            NavigationView {
                SubscriptionsView()
            }
            .tabItem {
                Label("Subscriptions", systemImage: "play.rectangle.fill")
                    .accessibility(label: Text("Subscriptions"))
            }
            .tag(TabSelection.subscriptions)

            NavigationView {
                PopularView()
            }
            .tabItem {
                Label("Popular", systemImage: "chart.bar")
                    .accessibility(label: Text("Popular"))
            }
            .tag(TabSelection.popular)

            NavigationView {
                TrendingView()
            }
            .tabItem {
                Label("Trending", systemImage: "chart.line.uptrend.xyaxis")
                    .accessibility(label: Text("Trending"))
            }
            .tag(TabSelection.trending)

            NavigationView {
                PlaylistsView()
            }
            .tabItem {
                Label("Playlists", systemImage: "list.and.film")
                    .accessibility(label: Text("Playlists"))
            }
            .tag(TabSelection.playlists)

            NavigationView {
                SearchView()
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
                    .accessibility(label: Text("Search"))
            }
            .tag(TabSelection.search)
        }
    }
}
