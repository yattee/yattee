import Defaults
import SwiftUI

struct AppTabNavigation: View {
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<SearchModel> private var search
    @EnvironmentObject<Recents> private var recents

    var body: some View {
        TabView(selection: $navigation.tabSelection) {
            NavigationView {
                LazyView(WatchNowView())
                    .toolbar { toolbarContent }
            }
            .tabItem {
                Label("Watch Now", systemImage: "play.circle")
                    .accessibility(label: Text("Subscriptions"))
            }
            .tag(TabSelection.watchNow)

            NavigationView {
                LazyView(SubscriptionsView())
                    .toolbar { toolbarContent }
            }
            .tabItem {
                Label("Subscriptions", systemImage: "star.circle.fill")
                    .accessibility(label: Text("Subscriptions"))
            }
            .tag(TabSelection.subscriptions)

//            TODO: reenable with settings
//            ============================
//            NavigationView {
//                LazyView(PopularView())
//                    .toolbar { toolbarContent }
//            }
//            .tabItem {
//                Label("Popular", systemImage: "chart.bar")
//                    .accessibility(label: Text("Popular"))
//            }
//            .tag(TabSelection.popular)

            NavigationView {
                LazyView(TrendingView())
                    .toolbar { toolbarContent }
            }
            .tabItem {
                Label("Trending", systemImage: "chart.line.uptrend.xyaxis")
                    .accessibility(label: Text("Trending"))
            }
            .tag(TabSelection.trending)

            NavigationView {
                LazyView(PlaylistsView())
                    .toolbar { toolbarContent }
            }
            .tabItem {
                Label("Playlists", systemImage: "list.and.film")
                    .accessibility(label: Text("Playlists"))
            }
            .tag(TabSelection.playlists)

            NavigationView {
                LazyView(
                    SearchView()
                        .toolbar { toolbarContent }
                        .searchable(text: $search.queryText, placement: .navigationBarDrawer(displayMode: .always)) {
                            ForEach(search.querySuggestions.collection, id: \.self) { suggestion in
                                Text(suggestion)
                                    .searchCompletion(suggestion)
                            }
                        }
                        .onChange(of: search.queryText) { query in
                            search.loadSuggestions(query)
                        }
                        .onSubmit(of: .search) {
                            search.changeQuery { query in
                                query.query = search.queryText
                            }

                            recents.open(RecentItem(from: search.queryText))

                            navigation.tabSelection = .search
                        }
                )
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
                    .accessibility(label: Text("Search"))
            }
            .tag(TabSelection.search)
        }
        .environment(\.navigationStyle, .tab)
        .sheet(isPresented: $navigation.isChannelOpen, onDismiss: {
            if let channel = recents.presentedChannel {
                let recent = RecentItem(from: channel)
                recents.close(recent)
            }
        }) {
            if recents.presentedChannel != nil {
                NavigationView {
                    ChannelVideosView(channel: recents.presentedChannel!)
                        .environment(\.inNavigationView, true)
                }
            }
        }
    }

    var toolbarContent: some ToolbarContent {
        #if os(iOS)
            Group {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button(action: { navigation.presentingSettings = true }) {
                        Image(systemName: "gearshape.2")
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    AccountsMenuView()
                }
            }
        #endif
    }
}
