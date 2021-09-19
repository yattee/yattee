import Defaults
import SwiftUI

struct AppTabNavigation: View {
    @EnvironmentObject<NavigationState> private var navigationState
    @EnvironmentObject<SearchState> private var searchState

    @EnvironmentObject<Recents> private var recents

    @State private var searchQuery = ""

    var body: some View {
        TabView(selection: $navigationState.tabSelection) {
            NavigationView {
                WatchNowView()
            }
            .tabItem {
                Label("Watch Now", systemImage: "play.circle")
                    .accessibility(label: Text("Subscriptions"))
            }
            .tag(TabSelection.watchNow)

            NavigationView {
                SubscriptionsView()
            }
            .tabItem {
                Label("Subscriptions", systemImage: "star.circle.fill")
                    .accessibility(label: Text("Subscriptions"))
            }
            .tag(TabSelection.subscriptions)

//            TODO: reenable with settings
//            ============================
//            NavigationView {
//                PopularView()
//            }
//            .tabItem {
//                Label("Popular", systemImage: "chart.bar")
//                    .accessibility(label: Text("Popular"))
//            }
//            .tag(TabSelection.popular)

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
                    .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always)) {
                        ForEach(searchState.querySuggestions.collection, id: \.self) { suggestion in
                            Text(suggestion)
                                .searchCompletion(suggestion)
                        }
                    }
                    .onChange(of: searchQuery) { query in
                        searchState.loadQuerySuggestions(query)
                    }
                    .onSubmit(of: .search) {
                        searchState.changeQuery { query in
                            query.query = self.searchQuery
                        }

                        navigationState.tabSelection = .search
                    }
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
                    .accessibility(label: Text("Search"))
            }
            .tag(TabSelection.search)
        }
        .sheet(isPresented: $navigationState.isChannelOpen, onDismiss: {
            if let channel = recents.presentedChannel {
                let recent = RecentItem(from: channel)
                recents.close(recent)
            }
        }) {
            if recents.presentedChannel != nil {
                NavigationView {
                    ChannelVideosView(recents.presentedChannel!)
                        .environment(\.inNavigationView, true)
                }
            }
        }
    }
}
