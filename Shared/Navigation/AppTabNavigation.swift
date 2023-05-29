import Defaults
import SwiftUI

struct AppTabNavigation: View {
    @ObservedObject private var accounts = AccountsModel.shared
    @ObservedObject private var navigation = NavigationModel.shared
    private var player = PlayerModel.shared
    @ObservedObject private var feed = FeedModel.shared
    @ObservedObject private var feedCount = UnwatchedFeedCountModel.shared
    private var recents = RecentsModel.shared

    @Default(.showHome) private var showHome
    @Default(.showDocuments) private var showDocuments
    @Default(.showOpenActionsToolbarItem) private var showOpenActionsToolbarItem
    @Default(.visibleSections) private var visibleSections
    @Default(.showUnwatchedFeedBadges) private var showUnwatchedFeedBadges

    let persistenceController = PersistenceController.shared

    var body: some View {
        TabView(selection: navigation.tabSelectionBinding) {
            Group {
                if showHome {
                    homeNavigationView
                }

                if showDocuments {
                    documentsNavigationView
                }

                if !accounts.isEmpty {
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
            }
            .modifier(PlayerOverlayModifier())
        }
        .onAppear {
            feed.calculateUnwatchedFeed()
        }
        .onChange(of: accounts.current) { _ in
            feed.calculateUnwatchedFeed()
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

    private var documentsNavigationView: some View {
        NavigationView {
            LazyView(DocumentsView())
                .toolbar { toolbarContent }
        }
        .tabItem {
            Label("Documents", systemImage: "folder")
                .accessibility(label: Text("Documents"))
        }
        .tag(TabSelection.documents)
    }

    private var subscriptionsNavigationView: some View {
        NavigationView {
            LazyView(SubscriptionsView())
        }
        .tabItem {
            Label("Subscriptions", systemImage: "star.circle.fill")
                .accessibility(label: Text("Subscriptions"))
        }
        .tag(TabSelection.subscriptions)
        .backport
        .badge(showUnwatchedFeedBadges ? feedCount.unwatchedText : nil)
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
                    if showOpenActionsToolbarItem {
                        Button(action: { navigation.presentingOpenVideos = true }) {
                            Label("Open Videos", systemImage: "play.circle.fill")
                        }
                    }
                    AccountViewButton()
                }
            }
        #endif
    }

    @ViewBuilder private var channelView: some View {
        if navigation.presentingChannel, let channel = recents.presentedChannel {
            NavigationView {
                ChannelVideosView(channel: channel, showCloseButton: true)
            }
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
            .environment(\.inChannelView, true)
            .environment(\.navigationStyle, .tab)
            .id("channelVideos")
            .zIndex(player.presentingPlayer ? -1 : 2)
            .transition(.move(edge: .bottom))
        }
    }

    @ViewBuilder private var playlistView: some View {
        if navigation.presentingPlaylist, let playlist = recents.presentedPlaylist {
            NavigationView {
                ChannelPlaylistView(playlist: playlist, showCloseButton: true)
            }
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
            .id("channelPlaylist")
            .zIndex(player.presentingPlayer ? -1 : 1)
            .transition(.move(edge: .bottom))
        }
    }
}

struct AppTabNavigation_Preview: PreviewProvider {
    static var previews: some View {
        AppTabNavigation()
    }
}
