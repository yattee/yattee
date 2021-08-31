import SwiftUI
#if os(iOS)
    import Introspect
#endif

struct AppSidebarNavigation: View {
    @EnvironmentObject<NavigationState> private var navigationState
    @EnvironmentObject<Playlists> private var playlists
    @EnvironmentObject<Subscriptions> private var subscriptions

    @State private var didApplyPrimaryViewWorkAround = false

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
    }

    var sidebar: some View {
        ScrollViewReader { scrollView in
            List {
                mainNavigationLinks

                Group {
                    AppSidebarRecentlyOpened(selection: selection)
                        .id("recentlyOpened")
                    AppSidebarSubscriptions(selection: selection)
                    AppSidebarPlaylists(selection: selection)
                }
                .onChange(of: navigationState.sidebarSectionChanged) { _ in
                    scrollScrollViewToItem(scrollView: scrollView, for: navigationState.tabSelection)
                }
            }
            .listStyle(.sidebar)
        }

        #if os(macOS)
            .toolbar {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.left").help("Toggle Sidebar")
                }
            }
        #endif
    }

    var mainNavigationLinks: some View {
        Group {
            NavigationLink(destination: SubscriptionsView(), tag: TabSelection.subscriptions, selection: selection) {
                Label("Subscriptions", systemImage: "star.circle.fill")
                    .accessibility(label: Text("Subscriptions"))
            }

            NavigationLink(destination: PopularView(), tag: TabSelection.popular, selection: selection) {
                Label("Popular", systemImage: "chart.bar")
                    .accessibility(label: Text("Popular"))
            }

            NavigationLink(destination: TrendingView(), tag: TabSelection.trending, selection: selection) {
                Label("Trending", systemImage: "chart.line.uptrend.xyaxis")
                    .accessibility(label: Text("Trending"))
            }

            NavigationLink(destination: PlaylistsView(), tag: TabSelection.playlists, selection: selection) {
                Label("Playlists", systemImage: "list.and.film")
                    .accessibility(label: Text("Playlists"))
            }

            NavigationLink(destination: SearchView(), tag: TabSelection.search, selection: selection) {
                Label("Search", systemImage: "magnifyingglass")
                    .accessibility(label: Text("Search"))
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
