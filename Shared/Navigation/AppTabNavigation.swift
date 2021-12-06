import Defaults
import SwiftUI

struct AppTabNavigation: View {
    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<CommentsModel> private var comments
    @EnvironmentObject<InstancesModel> private var instances
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<PlaylistsModel> private var playlists
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SearchModel> private var search
    @EnvironmentObject<SubscriptionsModel> private var subscriptions
    @EnvironmentObject<ThumbnailsModel> private var thumbnailsModel

    @Default(.visibleSections) private var visibleSections

    var body: some View {
        TabView(selection: navigation.tabSelectionBinding) {
            if visibleSections.contains(.favorites) {
                favoritesNavigationView
            }

            if subscriptionsVisible {
                subscriptionsNavigationView
            }

            if visibleSections.contains(.popular), accounts.app.supportsPopular, visibleSections.count < 5 {
                popularNavigationView
            }

            if visibleSections.contains(.trending) {
                trendingNavigationView
            }

            if visibleSections.contains(.playlists), accounts.app.supportsUserPlaylists {
                playlistsNavigationView
            }

            searchNavigationView
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
                            .environmentObject(subscriptions)
                            .background(playerNavigationLink)
                    }
                }
            }
        )
        .background(
            EmptyView().fullScreenCover(isPresented: $player.presentingPlayer) {
                videoPlayer
                    .environment(\.navigationStyle, .sidebar)
            }
        )
    }

    private var favoritesNavigationView: some View {
        NavigationView {
            LazyView(FavoritesView())
                .toolbar { toolbarContent }
        }
        .tabItem {
            Label("Favorites", systemImage: "heart")
                .accessibility(label: Text("Favorites"))
        }
        .tag(TabSelection.favorites)
    }

    private var subscriptionsNavigationView: some View {
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

    private var subscriptionsVisible: Bool {
        visibleSections.contains(.subscriptions) &&
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

    private var playlistsNavigationView: some View {
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

    private var searchNavigationView: some View {
        NavigationView {
            LazyView(SearchView())
                .toolbar { toolbarContent }
        }
        .tabItem {
            Label("Search", systemImage: "magnifyingglass")
                .accessibility(label: Text("Search"))
        }
        .tag(TabSelection.search)
    }

    private var playerNavigationLink: some View {
        NavigationLink(isActive: $player.playerNavigationLinkActive, destination: {
            VideoPlayerView()
                .environment(\.inNavigationView, true)
        }) {
            EmptyView()
        }
    }

    private var videoPlayer: some View {
        VideoPlayerView()
            .environmentObject(accounts)
            .environmentObject(comments)
            .environmentObject(instances)
            .environmentObject(navigation)
            .environmentObject(player)
            .environmentObject(playlists)
            .environmentObject(recents)
            .environmentObject(subscriptions)
            .environmentObject(thumbnailsModel)
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
