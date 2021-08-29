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
        List {
            mainNavigationLinks

            AppSidebarSubscriptions(selection: selection)
            AppSidebarPlaylists(selection: selection)
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
            NavigationLink(tag: TabSelection.subscriptions, selection: selection) {
                SubscriptionsView()
            }
            label: {
                Label("Subscriptions", systemImage: "star.circle.fill")
                    .accessibility(label: Text("Subscriptions"))
            }

            NavigationLink(tag: TabSelection.popular, selection: selection) {
                PopularView()
            }
            label: {
                Label("Popular", systemImage: "chart.bar")
                    .accessibility(label: Text("Popular"))
            }

            NavigationLink(tag: TabSelection.trending, selection: selection) {
                TrendingView()
            }
            label: {
                Label("Trending", systemImage: "chart.line.uptrend.xyaxis")
                    .accessibility(label: Text("Trending"))
            }

            NavigationLink(tag: TabSelection.playlists, selection: selection) {
                PlaylistsView()
            }
            label: {
                Label("Playlists", systemImage: "list.and.film")
                    .accessibility(label: Text("Playlists"))
            }

            NavigationLink(tag: TabSelection.search, selection: selection) {
                SearchView()
            }
            label: {
                Label("Search", systemImage: "magnifyingglass")
                    .accessibility(label: Text("Search"))
            }
        }
    }

    static func symbolSystemImage(_ name: String) -> String {
        let firstLetter = name.first?.lowercased()
        let regex = #"^[a-z0-9]$"#

        let symbolName = firstLetter?.range(of: regex, options: .regularExpression) != nil ? firstLetter! : "questionmark"

        return "\(symbolName).square"
    }

    #if os(macOS)
        private func toggleSidebar() {
            NSApp.keyWindow?.contentViewController?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
        }
    #endif
}
