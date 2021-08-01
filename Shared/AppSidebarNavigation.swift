import SwiftUI
#if os(iOS)
    import Introspect
#endif

typealias TabSelection = AppSidebarNavigation.TabSelection

struct AppSidebarNavigation: View {
    enum TabSelection: String {
        case subscriptions, popular, trending, playlists, channel, search
    }

    @EnvironmentObject<NavigationState> private var navigationState

    @State private var didApplyPrimaryViewWorkAround = false

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

            Text("Select video")
        }
    }

    var sidebar: some View {
        List {
            NavigationLink(tag: TabSelection.subscriptions, selection: navigationState.tabSelectionOptionalBinding) {
                SubscriptionsView()
            }
            label: {
                Label("Subscriptions", systemImage: "play.rectangle.fill")
                    .accessibility(label: Text("Subscriptions"))
            }

            NavigationLink(tag: TabSelection.popular, selection: navigationState.tabSelectionOptionalBinding) {
                PopularView()
            }
            label: {
                Label("Popular", systemImage: "chart.bar")
                    .accessibility(label: Text("Popular"))
            }

            NavigationLink(tag: TabSelection.trending, selection: navigationState.tabSelectionOptionalBinding) {
                TrendingView()
            }
            label: {
                Label("Trending", systemImage: "chart.line.uptrend.xyaxis")
                    .accessibility(label: Text("Trending"))
            }

            NavigationLink(tag: TabSelection.playlists, selection: navigationState.tabSelectionOptionalBinding) {
                PlaylistsView()
            }
            label: {
                Label("Playlists", systemImage: "list.and.film")
                    .accessibility(label: Text("Playlists"))
            }

            NavigationLink(tag: TabSelection.search, selection: navigationState.tabSelectionOptionalBinding) {
                SearchView()
            }
            label: {
                Label("Search", systemImage: "magnifyingglass")
                    .accessibility(label: Text("Search"))
            }
        }
        #if os(macOS)
            .toolbar {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.left").help("Toggle Sidebar")
                }
            }
        #endif
    }

    #if os(macOS)
        private func toggleSidebar() {
            NSApp.keyWindow?.contentViewController?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
        }
    #endif
}
