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

    @EnvironmentObject<InvidiousAPI> private var api
    @EnvironmentObject<InstancesModel> private var instances
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlaylistsModel> private var playlists
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    @State private var didApplyPrimaryViewWorkAround = false

    var selection: Binding<TabSelection?> {
        navigation.tabSelectionOptionalBinding
    }

    var body: some View {
        #if os(iOS)
            content.introspectViewController { viewController in
                // workaround for an empty supplementary view on launch
                // the supplementary view is determined by the default selection inside the
                // primary view, but the primary view is not loaded so its selection is not read
                // We work around that by showing the primary view
                if !didApplyPrimaryViewWorkAround, let splitVC = viewController.children.first as? UISplitViewController {
                    UIView.performWithoutAnimation {
                        splitVC.show(.primary)
                    }
                    didApplyPrimaryViewWorkAround = true
                }
            }
        #else
            content
        #endif
    }

    let sidebarMinWidth: Double = 280

    var content: some View {
        NavigationView {
            sidebar
                .toolbar { toolbarContent }
                .frame(minWidth: sidebarMinWidth)

            Text("Select section")
        }
        .environment(\.navigationStyle, .sidebar)
    }

    var sidebar: some View {
        ScrollViewReader { scrollView in
            List {
                ForEach(sidebarGroups) { group in
                    sidebarGroupContent(group)
                        .id(group)
                }

                .onChange(of: navigation.sidebarSectionChanged) { _ in
                    scrollScrollViewToItem(scrollView: scrollView, for: navigation.tabSelection)
                }
            }
            .listStyle(.sidebar)
        }
        .toolbar {
            toolbarContent
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

                AppSidebarRecents(selection: selection)
                    .id("recentlyOpened")

                if api.signedIn {
                    AppSidebarSubscriptions(selection: selection)
                    AppSidebarPlaylists(selection: selection)
                }
            }
        }
    }

    var mainNavigationLinks: some View {
        Section("Videos") {
            NavigationLink(destination: LazyView(WatchNowView()), tag: TabSelection.watchNow, selection: selection) {
                Label("Watch Now", systemImage: "play.circle")
                    .accessibility(label: Text("Watch Now"))
            }

            if api.signedIn {
                NavigationLink(destination: LazyView(SubscriptionsView()), tag: TabSelection.subscriptions, selection: selection) {
                    Label("Subscriptions", systemImage: "star.circle")
                        .accessibility(label: Text("Subscriptions"))
                }
            }

            NavigationLink(destination: LazyView(PopularView()), tag: TabSelection.popular, selection: selection) {
                Label("Popular", systemImage: "chart.bar")
                    .accessibility(label: Text("Popular"))
            }

            NavigationLink(destination: LazyView(TrendingView()), tag: TabSelection.trending, selection: selection) {
                Label("Trending", systemImage: "chart.line.uptrend.xyaxis")
                    .accessibility(label: Text("Trending"))
            }

            NavigationLink(destination: LazyView(SearchView()), tag: TabSelection.search, selection: selection) {
                Label("Search", systemImage: "magnifyingglass")
                    .accessibility(label: Text("Search"))
            }
            .keyboardShortcut("f")
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

    var toolbarContent: some ToolbarContent {
        Group {
            #if os(iOS)
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { navigation.presentingSettings = true }) {
                        Image(systemName: "gearshape.2")
                    }
                }
            #endif

            ToolbarItem(placement: accountsMenuToolbarItemPlacement) {
                AccountsMenuView()
                    .help(
                        "Switch Instances and Accounts\n" +
                            "Current Instance: \n" +
                            "\(api.account?.url ?? "Not Set")\n" +
                            "Current User: \(api.account?.description ?? "Not set")"
                    )
            }
        }
    }

    var accountsMenuToolbarItemPlacement: ToolbarItemPlacement {
        #if os(iOS)
            return .bottomBar
        #else
            return .automatic
        #endif
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

        return "\(symbolName).circle"
    }
}
