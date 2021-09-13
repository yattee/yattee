import SwiftUI
#if os(iOS)
    import Introspect
#endif

struct AppSidebarNavigation: View {
    enum SidebarGroup: String, Identifiable {
        case main

        var id: RawValue {
            rawValue
        }
    }

    @EnvironmentObject<NavigationState> private var navigationState
    @EnvironmentObject<Playlists> private var playlists
    @EnvironmentObject<SearchState> private var searchState
    @EnvironmentObject<Subscriptions> private var subscriptions

    @State private var didApplyPrimaryViewWorkAround = false

    @State private var searchQuery = ""

    var selection: Binding<TabSelection?> {
        navigationState.tabSelectionOptionalBinding
    }

    var body: some View {
        #if os(iOS)
            content.introspectViewController { viewController in
                // workaround for an empty supplementary view on launch
                // the supplementary view is determined by the default selection inside the
                // primary view, but the primary view is not loaded so its selection is not read
                // We work around that by briefly showing the primary view.
                if !didApplyPrimaryViewWorkAround, let splitVC = viewController.children.first as? UISplitViewController {
                    UIView.performWithoutAnimation {
                        splitVC.show(.primary)
                        splitVC.hide(.primary)
                    }
                    didApplyPrimaryViewWorkAround = true
                }
            }
        #else
            content
        #endif
    }

    var content: some View {
        NavigationView {
            sidebar
                .frame(minWidth: 180)

            Text("Select section")
        }
        .searchable(text: $searchQuery, placement: .sidebar) {
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

    var sidebar: some View {
        ScrollViewReader { scrollView in
            List {
                ForEach(sidebarGroups) { group in
                    sidebarGroupContent(group)
                        .id(group)
                }

                .onChange(of: navigationState.sidebarSectionChanged) { _ in
                    scrollScrollViewToItem(scrollView: scrollView, for: navigationState.tabSelection)
                }
            }
            .background {
                NavigationLink(destination: SearchView(), tag: TabSelection.search, selection: selection) {
                    Color.clear
                }
                .hidden()
            }
            .listStyle(.sidebar)
        }
        .toolbar {
            #if os(macOS)
                ToolbarItemGroup {
                    Button(action: toggleSidebar) {
                        Image(systemName: "sidebar.left").help("Toggle Sidebar")
                    }
                }
            #endif
        }
    }

    var sidebarGroups: [SidebarGroup] {
        [.main]
    }

    func sidebarGroupContent(_ group: SidebarGroup) -> some View {
        switch group {
        case .main:
            return Group {
                mainNavigationLinks

                AppSidebarRecentlyOpened(selection: selection)
                    .id("recentlyOpened")
                AppSidebarSubscriptions(selection: selection)
                AppSidebarPlaylists(selection: selection)
            }
        }
    }

    var mainNavigationLinks: some View {
        Section("Videos") {
            NavigationLink(destination: LazyView(SubscriptionsView()), tag: TabSelection.subscriptions, selection: selection) {
                Label("Subscriptions", systemImage: "star.circle.fill")
                    .accessibility(label: Text("Subscriptions"))
            }

            NavigationLink(destination: LazyView(PopularView()), tag: TabSelection.popular, selection: selection) {
                Label("Popular", systemImage: "chart.bar")
                    .accessibility(label: Text("Popular"))
            }

            NavigationLink(destination: LazyView(TrendingView()), tag: TabSelection.trending, selection: selection) {
                Label("Trending", systemImage: "chart.line.uptrend.xyaxis")
                    .accessibility(label: Text("Trending"))
            }

            NavigationLink(destination: LazyView(PlaylistsView()), tag: TabSelection.playlists, selection: selection) {
                Label("Playlists", systemImage: "list.and.film")
                    .accessibility(label: Text("Playlists"))
            }
        }
    }

    func scrollScrollViewToItem(scrollView: ScrollViewProxy, for selection: TabSelection) {
        if case let .channel(id) = selection {
            if subscriptions.isSubscribing(id) {
                scrollView.scrollTo(id)
            } else {
                scrollView.scrollTo("recentlyOpened")
            }
        } else if case let .playlist(id) = selection {
            scrollView.scrollTo(id)
        }
    }

    #if os(macOS)
        private func toggleSidebar() {
            NSApp.keyWindow?.contentViewController?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
        }
    #endif

    static func symbolSystemImage(_ name: String) -> String {
        let firstLetter = name.first?.lowercased()
        let regex = #"^[a-z0-9]$"#

        let symbolName = firstLetter?.range(of: regex, options: .regularExpression) != nil ? firstLetter! : "questionmark"

        return "\(symbolName).square"
    }
}
