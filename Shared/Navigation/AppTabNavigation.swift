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

    let persistenceController = PersistenceController.shared

    var body: some View {
        TabView(selection: navigation.tabSelectionBinding) {
            if visibleSections.contains(.home) {
                homeNavigationView
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

            if playlistsVisible {
                playlistsNavigationView
            }

            searchNavigationView
        }
        .id(accounts.current?.id ?? "")
        .overlay(playlistView)
        .overlay(channelView)
        .environment(\.navigationStyle, .tab)
    }

    private var homeNavigationView: some View {
        NavigationView {
            LazyView(HomeView())
                .toolbar { toolbarContent }
        }
        .tabItem {
            Label("Home", systemImage: "house.fill")
                .accessibility(label: Text("Home"))
        }
        .tag(TabSelection.home)
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

    private var playlistsVisible: Bool {
        visibleSections.contains(.playlists) &&
            accounts.app.supportsUserPlaylists && !(accounts.current?.anonymous ?? true)
    }

    private var popularNavigationView: some View {
        NavigationView {
            LazyView(PopularView())
                .toolbar { toolbarContent }
        }
        .tabItem {
            Label("Popular", systemImage: "arrow.up.right.circle.fill")
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
            Label("Trending", systemImage: "chart.bar.fill")
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

    var toolbarContent: some ToolbarContent {
        #if os(iOS)
            Group {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button(action: { navigation.presentingSettings = true }) {
                        Image(systemName: "gearshape.2")
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { navigation.presentingOpenVideos = true }) {
                        Label("Open Videos", systemImage: "play.circle.fill")
                    }
                    AccountsMenuView()
                }
            }
        #endif
    }

    @ViewBuilder private var channelView: some View {
        if navigation.presentingChannel {
            ChannelVideosView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(\.inChannelView, true)
                .environment(\.navigationStyle, .tab)
                .environmentObject(accounts)
                .environmentObject(navigation)
                .environmentObject(player)
                .environmentObject(subscriptions)
                .environmentObject(thumbnailsModel)
                .id("channelVideos")
                .zIndex(player.presentingPlayer ? -1 : 2)
                .transition(.move(edge: .bottom))
        }
    }

    @ViewBuilder private var playlistView: some View {
        if navigation.presentingPlaylist {
            ChannelPlaylistView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(accounts)
                .environmentObject(navigation)
                .environmentObject(player)
                .environmentObject(subscriptions)
                .environmentObject(thumbnailsModel)
                .id("channelPlaylist")
                .zIndex(player.presentingPlayer ? -1 : 1)
                .transition(.move(edge: .bottom))
        }
    }
}
