import SwiftUI

struct Sidebar: View {
    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlaylistsModel> private var playlists
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    var body: some View {
        ScrollViewReader { scrollView in
            List {
                if !accounts.isEmpty {
                    mainNavigationLinks

                    AppSidebarRecents()
                        .id("recentlyOpened")

                    if accounts.api.signedIn {
                        if accounts.app.supportsSubscriptions {
                            AppSidebarSubscriptions()
                        }

                        if accounts.app.supportsUserPlaylists {
                            AppSidebarPlaylists()
                        }
                    }
                }
            }
            .onAppear {
                subscriptions.load()
                playlists.load()
            }
            .onChange(of: accounts.signedIn) { _ in
                subscriptions.load(force: true)
                playlists.load(force: true)
            }
            .onChange(of: navigation.sidebarSectionChanged) { _ in
                scrollScrollViewToItem(scrollView: scrollView, for: navigation.tabSelection)
            }
            .listStyle(.sidebar)
        }
        .navigationTitle("Yattee")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    var mainNavigationLinks: some View {
        Section("Videos") {
            NavigationLink(destination: LazyView(FavoritesView()), tag: TabSelection.favorites, selection: $navigation.tabSelection) {
                Label("Favorites", systemImage: "heart")
                    .accessibility(label: Text("Favorites"))
            }
            if accounts.app.supportsSubscriptions && accounts.signedIn {
                NavigationLink(destination: LazyView(SubscriptionsView()), tag: TabSelection.subscriptions, selection: $navigation.tabSelection) {
                    Label("Subscriptions", systemImage: "star.circle")
                        .accessibility(label: Text("Subscriptions"))
                }
            }

            if accounts.app.supportsPopular {
                NavigationLink(destination: LazyView(PopularView()), tag: TabSelection.popular, selection: $navigation.tabSelection) {
                    Label("Popular", systemImage: "chart.bar")
                        .accessibility(label: Text("Popular"))
                }
            }

            NavigationLink(destination: LazyView(TrendingView()), tag: TabSelection.trending, selection: $navigation.tabSelection) {
                Label("Trending", systemImage: "chart.line.uptrend.xyaxis")
                    .accessibility(label: Text("Trending"))
            }

            NavigationLink(destination: LazyView(SearchView()), tag: TabSelection.search, selection: $navigation.tabSelection) {
                Label("Search", systemImage: "magnifyingglass")
                    .accessibility(label: Text("Search"))
            }
            .keyboardShortcut("f")
        }
    }

    func scrollScrollViewToItem(scrollView: ScrollViewProxy, for selection: TabSelection) {
        if case .recentlyOpened = selection {
            scrollView.scrollTo("recentlyOpened")
        } else if case let .playlist(id) = selection {
            scrollView.scrollTo(id)
        }
    }
}
