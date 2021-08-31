import Defaults
import SwiftUI

struct AppTabNavigation: View {
    @EnvironmentObject<NavigationState> private var navigationState

    var body: some View {
        TabView(selection: $navigationState.tabSelection) {
            NavigationView {
                SubscriptionsView()
            }
            .tabItem {
                Label("Subscriptions", systemImage: "star.circle.fill")
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
        .sheet(isPresented: $navigationState.isChannelOpen, onDismiss: {
            navigationState.closeChannel(presentedChannel)
        }) {
            if presentedChannel != nil {
                NavigationView {
                    ChannelVideosView(presentedChannel)
                        .environment(\.inNavigationView, true)
                }
            }
        }
    }

    fileprivate var presentedChannel: Channel! {
        navigationState.openChannels.first
    }
}
