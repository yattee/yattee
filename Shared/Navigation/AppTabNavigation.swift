import Defaults
import SwiftUI

struct AppTabNavigation: View {
    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SearchModel> private var search

    var body: some View {
        TabView(selection: navigation.tabSelectionBinding) {
            NavigationView {
                LazyView(WatchNowView())
                    .toolbar { toolbarContent }
            }
            .tabItem {
                Label("Watch Now", systemImage: "play.circle")
                    .accessibility(label: Text("Subscriptions"))
            }
            .tag(TabSelection.watchNow)

            if accounts.app.supportsSubscriptions {
                NavigationView {
                    LazyView(SubscriptionsView())
                        .toolbar { toolbarContent }
                }
                .tabItem {
                    Label("Subscriptions", systemImage: "star.circle.fill")
                        .accessibility(label: Text("Subscriptions"))
                }
                .tag(TabSelection.subscriptions)
            }

            // TODO: reenable with settings
            if accounts.app.supportsPopular && false {
                NavigationView {
                    LazyView(PopularView())
                        .toolbar { toolbarContent }
                }
                .tabItem {
                    Label("Popular", systemImage: "chart.bar")
                        .accessibility(label: Text("Popular"))
                }
                .tag(TabSelection.popular)
            }

            NavigationView {
                LazyView(TrendingView())
                    .toolbar { toolbarContent }
            }
            .tabItem {
                Label("Trending", systemImage: "chart.line.uptrend.xyaxis")
                    .accessibility(label: Text("Trending"))
            }
            .tag(TabSelection.trending)

            if accounts.app.supportsUserPlaylists {
                NavigationView {
                    LazyView(PlaylistsView())
                        .toolbar { toolbarContent }
                }
                .tabItem {
                    Label("Playlists", systemImage: "list.and.film")
                        .accessibility(label: Text("Playlists"))
                }
                .tag(TabSelection.playlists)
            }

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

                            recents.addQuery(search.queryText)
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
        .sheet(isPresented: $navigation.presentingChannel, onDismiss: {
            if let channel = recents.presentedChannel {
                recents.close(RecentItem(from: channel))
            }
        }) {
            if let channel = recents.presentedChannel {
                NavigationView {
                    ChannelVideosView(channel: channel)
                        .environment(\.inChannelView, true)
                        .environment(\.inNavigationView, true)
                        .background(playerNavigationLink)
                }
            }
        }
        .sheet(isPresented: $navigation.presentingPlaylist, onDismiss: {
            if let playlist = recents.presentedPlaylist {
                recents.close(RecentItem(from: playlist))
            }
        }) {
            if let playlist = recents.presentedPlaylist {
                NavigationView {
                    ChannelPlaylistView(playlist: playlist)
                        .environment(\.inNavigationView, true)
                        .background(playerNavigationLink)
                }
            }
        }
    }

    private var playerNavigationLink: some View {
        NavigationLink(isActive: $player.playerNavigationLinkActive, destination: {
            VideoPlayerView()
                .environment(\.inNavigationView, true)
        }) {
            EmptyView()
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
