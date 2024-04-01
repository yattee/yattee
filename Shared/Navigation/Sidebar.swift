import Defaults
import SwiftUI

struct Sidebar: View {
    @ObservedObject private var accounts = AccountsModel.shared
    @ObservedObject private var navigation = NavigationModel.shared
    @ObservedObject private var feed = FeedModel.shared
    @ObservedObject private var feedCount = UnwatchedFeedCountModel.shared

    @Default(.showHome) private var showHome
    @Default(.visibleSections) private var visibleSections
    #if os(iOS)
        @Default(.showDocuments) private var showDocuments
    #endif
    @Default(.showUnwatchedFeedBadges) private var showUnwatchedFeedBadges
    @Default(.showRecents) private var showRecents

    var body: some View {
        ScrollViewReader { scrollView in
            List {
                mainNavigationLinks

                if !accounts.isEmpty {
                    if showRecents {
                        AppSidebarRecents()
                            .id("recentlyOpened")
                    }

                    if accounts.api.signedIn {
                        if visibleSections.contains(.subscriptions), accounts.app.supportsSubscriptions {
                            AppSidebarSubscriptions()
                        }

                        if visibleSections.contains(.playlists), accounts.app.supportsUserPlaylists {
                            AppSidebarPlaylists()
                        }
                    }
                }
            }
            .onChange(of: navigation.sidebarSectionChanged) { _ in
                if let tabSelection = navigation.tabSelection {
                    scrollScrollViewToItem(scrollView: scrollView, for: tabSelection)
                }
            }
            .listStyle(.sidebar)
        }
        .onAppear {
            feed.calculateUnwatchedFeed()
        }
        .onChange(of: accounts.current) { _ in
            feed.calculateUnwatchedFeed()
        }
        .navigationTitle("Yattee")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    var mainNavigationLinks: some View {
        Section(header: Text("Videos")) {
            if showHome {
                NavigationLink(destination: LazyView(HomeView()), tag: TabSelection.home, selection: $navigation.tabSelection) {
                    Label("Home", systemImage: "house")
                        .accessibility(label: Text("Home"))
                }
                .id("home")
            }

            #if os(iOS)
                if showDocuments {
                    NavigationLink(destination: LazyView(DocumentsView()), tag: TabSelection.documents, selection: $navigation.tabSelection) {
                        Label("Documents", systemImage: "folder")
                            .accessibility(label: Text("Documents"))
                    }
                    .id("documents")
                }
            #endif

            if !accounts.isEmpty {
                if visibleSections.contains(.subscriptions),
                   accounts.app.supportsSubscriptions && accounts.signedIn
                {
                    NavigationLink(destination: LazyView(SubscriptionsView()), tag: TabSelection.subscriptions, selection: $navigation.tabSelection) {
                        Label("Subscriptions", systemImage: "star.circle")
                            .accessibility(label: Text("Subscriptions"))
                    }
                    .backport
                    .badge(showUnwatchedFeedBadges ? feedCount.unwatchedText : nil)
                    .contextMenu {
                        playUnwatchedButton
                        toggleWatchedButton
                    }
                    .id("subscriptions")
                }

                if visibleSections.contains(.popular), accounts.app.supportsPopular {
                    NavigationLink(destination: LazyView(PopularView()), tag: TabSelection.popular, selection: $navigation.tabSelection) {
                        Label("Popular", systemImage: "arrow.up.right.circle")
                            .accessibility(label: Text("Popular"))
                    }
                    .id("popular")
                }

                if visibleSections.contains(.trending) {
                    NavigationLink(destination: LazyView(TrendingView()), tag: TabSelection.trending, selection: $navigation.tabSelection) {
                        Label("Trending", systemImage: "chart.bar")
                            .accessibility(label: Text("Trending"))
                    }
                    .id("trending")
                }

                NavigationLink(destination: LazyView(SearchView()), tag: TabSelection.search, selection: $navigation.tabSelection) {
                    Label("Search", systemImage: "magnifyingglass")
                        .accessibility(label: Text("Search"))
                }
                .id("search")
                .keyboardShortcut("f")
            }
        }
    }

    var playUnwatchedButton: some View {
        Button {
            feed.playUnwatchedFeed()
        } label: {
            Label("Play all unwatched", systemImage: "play")
        }
        .disabled(!feed.canPlayUnwatchedFeed)
    }

    @ViewBuilder var toggleWatchedButton: some View {
        if feed.canMarkAllFeedAsWatched {
            markAllFeedAsWatchedButton
        } else {
            markAllFeedAsUnwatchedButton
        }
    }

    var markAllFeedAsWatchedButton: some View {
        Button {
            feed.markAllFeedAsWatched()
        } label: {
            Label("Mark all as watched", systemImage: "checkmark.circle.fill")
        }
        .disabled(!feed.canMarkAllFeedAsWatched)
    }

    var markAllFeedAsUnwatchedButton: some View {
        Button {
            feed.markAllFeedAsUnwatched()
        } label: {
            Label("Mark all as unwatched", systemImage: "checkmark.circle")
        }
    }

    private func scrollScrollViewToItem(scrollView: ScrollViewProxy, for selection: TabSelection!) {
        guard let selection else { return }

        if case .recentlyOpened = selection {
            scrollView.scrollTo("recentlyOpened")
            return
        }
        if case let .playlist(id) = selection {
            scrollView.scrollTo(id)
            return
        }

        scrollView.scrollTo(selection.stringValue)
    }
}

struct Sidebar_Previews: PreviewProvider {
    static var previews: some View {
        Sidebar()
    }
}
