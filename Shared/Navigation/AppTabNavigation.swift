import Defaults
import SwiftUI

struct AppTabNavigation: View {
    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SearchModel> private var search

    @Default(.tabNavigationSection) private var tabNavigationSection

    var body: some View {
        TabView(selection: navigation.tabSelectionBinding) {
            NavigationView {
                LazyView(FavoritesView())
                    .toolbar { toolbarContent }
            }
            .tabItem {
                Label("Favorites", systemImage: "heart")
                    .accessibility(label: Text("Favorites"))
            }
            .tag(TabSelection.favorites)

            if subscriptionsVisible {
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

            if subscriptionsVisible {
                if accounts.app.supportsPopular {
                    if tabNavigationSection == .popular {
                        popularNavigationView
                    } else {
                        trendingNavigationView
                    }
                } else {
                    trendingNavigationView
                }
            } else {
                if accounts.app.supportsPopular {
                    popularNavigationView
                }
                trendingNavigationView
            }

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
                LazyView(SearchView())
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
                    .accessibility(label: Text("Search"))
            }
            .tag(TabSelection.search)
        }
        .id(accounts.current?.id ?? "")
        .environment(\.navigationStyle, .tab)
        .background(
            EmptyView().sheet(isPresented: $navigation.presentingChannel, onDismiss: {
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
        )
        .background(
            EmptyView().sheet(isPresented: $navigation.presentingPlaylist, onDismiss: {
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
        )
    }

    private var subscriptionsVisible: Bool {
        accounts.app.supportsSubscriptions && !(accounts.current?.anonymous ?? true)
    }

    private var popularNavigationView: some View {
        NavigationView {
            LazyView(PopularView())
                .toolbar { toolbarContent }
        }
        .tabItem {
            Label("Popular", systemImage: "arrow.up.right.circle")
                .accessibility(label: Text("Popular"))
        }
        .tag(TabSelection.popular)
    }

    private var trendingNavigationView: some View {
        NavigationView {
            LazyView(TrendingView())
                .toolbar { toolbarContent }
        }
        .tabItem {
            Label("Trending", systemImage: "chart.bar")
                .accessibility(label: Text("Trending"))
        }
        .tag(TabSelection.trending)
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
