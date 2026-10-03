//
//  CompactTabView.swift
//  Yattee
//
//  Custom tab bar for compact size class (iPhone, iPad Stage Manager small window).
//  Uses settings-based tab customization since Apple's TabViewCustomization only works in sidebar mode.
//

import SwiftUI

#if os(iOS)
struct CompactTabView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let router: NavigationRouter

    // Zoom transition namespace (local to this tab view)
    @Namespace private var zoomTransition

    private var settingsManager: SettingsManager? {
        appEnvironment?.settingsManager
    }

    /// Returns the visible custom tabs from settings
    private var visibleTabItems: [TabBarItem] {
        settingsManager?.visibleTabBarItems() ?? []
    }

    /// Whether to show the mini player accessory (iOS 26.1+)
    private var shouldShowAccessory: Bool {
        guard let state = appEnvironment?.playerService.state else { return false }
        return state.currentVideo != nil && !state.isClosingVideo
    }

    private var zoomTransitionsEnabled: Bool {
        appEnvironment?.settingsManager.zoomTransitionsEnabled ?? true
    }

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selection) {
            // Fixed: Home (first)
            Tab(value: SidebarItem.home) {
                NavigationStack(path: router.path(for: .home)) {
                    HomeView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(String(localized: "tabs.home"), systemImage: "house.fill")
            }
            .accessibilityIdentifier("tab.home")

            // Dynamic tabs from settings (in the middle, SwiftUI auto-collapses overflow into More)
            ForEach(visibleTabItems) { item in
                Tab(value: Self.sidebarItem(for: item)) {
                    NavigationStack(path: router.path(for: Self.sidebarItem(for: item))) {
                        tabContent(for: item)
                            .withNavigationDestinations()
                    }
                } label: {
                    Label(item.localizedTitle, systemImage: item.icon)
                }
            }

            // Fixed: Search (last) - with role: .search
            Tab(value: SidebarItem.search, role: .search) {
                NavigationStack(path: router.path(for: .search)) {
                    SearchView(searchText: $router.searchText)
                        .withNavigationDestinations()
                }
            } label: {
                Label(String(localized: "tabs.search"), systemImage: "magnifyingglass")
            }
            .accessibilityIdentifier("tab.search")
        }
        .zoomTransitionNamespace(zoomTransition)
        .zoomTransitionsEnabled(zoomTransitionsEnabled)
        .iOS26TabFeatures(shouldShowAccessory: shouldShowAccessory, settingsManager: settingsManager)
        .onAppear {
            router.applyStartupTabIfNeeded(settingsManager?.effectiveStartupTabForTabBar() ?? .home)
            ensureSelectionIsAvailable()
        }
        .onChange(of: router.selection) { _, _ in
            ensureSelectionIsAvailable()
        }
        .onChange(of: visibleTabItems) { _, _ in
            ensureSelectionIsAvailable()
        }
    }

    // MARK: - Layout Mapping

    private static func sidebarItem(for item: TabBarItem) -> SidebarItem {
        SidebarMainItem(tabBarItem: item)?.sidebarItem ?? .home
    }

    /// Sidebar-only selections (channels, playlists, sources) and tabs hidden
    /// by customization are remapped onto a tab that can host them.
    private func ensureSelectionIsAvailable() {
        let available = Set([SidebarItem.home, .search] + visibleTabItems.map(Self.sidebarItem(for:)))
        router.ensureSelectionIsAvailable(
            isAvailable: { available.contains($0) },
            instance: { id in appEnvironment?.instancesManager.enabledInstances.first { $0.id == id } }
        )
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(for item: TabBarItem) -> some View {
        switch item {
        case .subscriptions:
            SubscriptionsView()
        case .channels:
            ManageChannelsView()
        case .bookmarks:
            BookmarksListView()
        case .playlists:
            PlaylistsListView()
        case .history:
            HistoryListView()
        case .downloads:
            DownloadsView()
        case .sources:
            MediaSourcesView()
        case .settings:
            SettingsView(showCloseButton: false)
        case .continueWatching:
            ContinueWatchingView()
        }
    }
}

// MARK: - Preview

#Preview {
    CompactTabView(router: NavigationRouter())
        .appEnvironment(.preview)
}
#endif
