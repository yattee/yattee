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

    // Navigation paths for fixed tabs
    @State private var homePath = NavigationPath()
    @State private var searchPath = NavigationPath()

    // Navigation paths for dynamic tabs
    @State private var subscriptionsPath = NavigationPath()
    @State private var channelsPath = NavigationPath()
    @State private var bookmarksPath = NavigationPath()
    @State private var playlistsPath = NavigationPath()
    @State private var historyPath = NavigationPath()
    @State private var downloadsPath = NavigationPath()
    @State private var sourcesPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var continueWatchingPath = NavigationPath()

    // Tab selection - using String to support both fixed and dynamic tabs
    // Initial value is a placeholder; actual startup tab is applied in onAppear
    @State private var selectedTab: String = "home"
    @State private var hasAppliedStartupTab = false

    // Search text state (iOS 26+ TabView .searchable integration)
    @State private var searchText = ""

    // Zoom transition namespace (local to this tab view)
    @Namespace private var zoomTransition

    private var settingsManager: SettingsManager? {
        appEnvironment?.settingsManager
    }

    private var navigationCoordinator: NavigationCoordinator? {
        appEnvironment?.navigationCoordinator
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
        TabView(selection: $selectedTab) {
            // Fixed: Home (first)
            Tab(value: "home") {
                NavigationStack(path: $homePath) {
                    HomeView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(String(localized: "tabs.home"), systemImage: "house.fill")
            }
            .accessibilityIdentifier("tab.home")

            // Dynamic tabs from settings (in the middle, SwiftUI auto-collapses overflow into More)
            ForEach(visibleTabItems) { item in
                Tab(value: item.rawValue) {
                    tabContent(for: item)
                } label: {
                    Label(item.localizedTitle, systemImage: item.icon)
                }
            }

            // Fixed: Search (last) - with role: .search
            Tab(value: "search", role: .search) {
                NavigationStack(path: $searchPath) {
                    SearchView(searchText: $searchText)
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
        .onChange(of: navigationCoordinator?.pendingNavigation) { _, newValue in
            handlePendingNavigation(newValue)
        }
        .onChange(of: selectedTab) { _, newTab in
            updateHandoffForTab(newTab)
            syncTabToCoordinator(newTab)
        }
        .onChange(of: navigationCoordinator?.selectedTab) { _, newTab in
            syncTabFromCoordinator(newTab)
        }
        .onAppear {
            applyStartupTabIfNeeded()
        }
    }

    // MARK: - Startup Tab

    /// Applies the configured startup tab on first appearance.
    private func applyStartupTabIfNeeded() {
        guard !hasAppliedStartupTab else { return }
        hasAppliedStartupTab = true

        let startupTab = settingsManager?.effectiveStartupTabForTabBar() ?? .home
        selectedTab = startupTab.compactTabValue
    }

    // MARK: - Handoff

    /// Updates Handoff activity based on the selected tab.
    private func updateHandoffForTab(_ tab: String) {
        let destination: NavigationDestination?

        switch tab {
        case "home":
            // Home tab - use playlists as default (matches HomeView's primary content)
            destination = .playlists
        case "search":
            // Search updates handoff when a search is performed
            destination = nil
        case TabBarItem.subscriptions.rawValue:
            destination = .subscriptionsFeed
        case TabBarItem.channels.rawValue:
            destination = .manageChannels
        case TabBarItem.bookmarks.rawValue:
            destination = .bookmarks
        case TabBarItem.playlists.rawValue:
            destination = .playlists
        case TabBarItem.history.rawValue:
            destination = .history
        case TabBarItem.downloads.rawValue:
            destination = .downloads
        case TabBarItem.sources.rawValue:
            destination = nil  // No handoff for sources
        case TabBarItem.settings.rawValue:
            destination = nil  // No handoff for settings
        default:
            destination = nil
        }

        if let destination {
            appEnvironment?.handoffManager.updateActivity(for: destination)
        }
    }

    // MARK: - Tab Sync with NavigationCoordinator

    /// Syncs NavigationCoordinator's selectedTab to local state (coordinator → local).
    /// Called when NavigationCoordinator.selectedTab changes (e.g., from notification tap).
    private func syncTabFromCoordinator(_ appTab: AppTab?) {
        guard let appTab else { return }

        switch appTab {
        case .home:
            if selectedTab != "home" {
                selectedTab = "home"
            }
        case .subscriptions:
            if visibleTabItems.contains(.subscriptions) {
                // Subscriptions tab is visible - switch to it
                let tabValue = TabBarItem.subscriptions.rawValue
                if selectedTab != tabValue {
                    selectedTab = tabValue
                }
            } else {
                // Subscriptions tab not visible - push subscriptions view onto current stack
                pushSubscriptionsOnCurrentStack()
            }
        case .search:
            if selectedTab != "search" {
                selectedTab = "search"
            }
        #if os(tvOS)
        case .settings:
            break
        #endif
        }
    }

    /// Syncs local selectedTab to NavigationCoordinator (local → coordinator).
    /// Called when user manually switches tabs.
    private func syncTabToCoordinator(_ tab: String) {
        guard let coordinator = navigationCoordinator else { return }

        let appTab: AppTab
        switch tab {
        case "home":
            appTab = .home
        case "search":
            appTab = .search
        case TabBarItem.subscriptions.rawValue:
            appTab = .subscriptions
        default:
            // Other tabs (channels, bookmarks, downloads, etc.) don't have AppTab equivalents
            // Don't update coordinator - just return to avoid feedback loop
            return
        }

        if coordinator.selectedTab != appTab {
            coordinator.selectedTab = appTab
        }
    }

    /// Pushes the subscriptions feed onto the current tab's navigation stack.
    /// Used when subscriptions tab is not visible but we need to navigate to subscriptions.
    private func pushSubscriptionsOnCurrentStack() {
        let destination = NavigationDestination.subscriptionsFeed
        switch selectedTab {
        case "home":
            homePath.append(destination)
        case "search":
            searchPath.append(destination)
        case TabBarItem.channels.rawValue:
            channelsPath.append(destination)
        case TabBarItem.bookmarks.rawValue:
            bookmarksPath.append(destination)
        case TabBarItem.playlists.rawValue:
            playlistsPath.append(destination)
        case TabBarItem.history.rawValue:
            historyPath.append(destination)
        case TabBarItem.downloads.rawValue:
            downloadsPath.append(destination)
        case TabBarItem.sources.rawValue:
            sourcesPath.append(destination)
        case TabBarItem.settings.rawValue:
            settingsPath.append(destination)
        case TabBarItem.continueWatching.rawValue:
            continueWatchingPath.append(destination)
        default:
            homePath.append(destination)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(for item: TabBarItem) -> some View {
        switch item {
        case .subscriptions:
            NavigationStack(path: $subscriptionsPath) {
                SubscriptionsView()
                    .withNavigationDestinations()
            }
        case .channels:
            NavigationStack(path: $channelsPath) {
                ManageChannelsView()
                    .withNavigationDestinations()
            }
        case .bookmarks:
            NavigationStack(path: $bookmarksPath) {
                BookmarksListView()
                    .withNavigationDestinations()
            }
        case .playlists:
            NavigationStack(path: $playlistsPath) {
                PlaylistsListView()
                    .withNavigationDestinations()
            }
        case .history:
            NavigationStack(path: $historyPath) {
                HistoryListView()
                    .withNavigationDestinations()
            }
        case .downloads:
            NavigationStack(path: $downloadsPath) {
                DownloadsView()
                    .withNavigationDestinations()
            }
        case .sources:
            NavigationStack(path: $sourcesPath) {
                MediaSourcesView()
                    .withNavigationDestinations()
            }
        case .settings:
            NavigationStack(path: $settingsPath) {
                SettingsView(showCloseButton: false)
                    .withNavigationDestinations()
            }
        case .continueWatching:
            NavigationStack(path: $continueWatchingPath) {
                ContinueWatchingView()
                    .withNavigationDestinations()
            }
        }
    }

    // MARK: - Navigation Handling

    private func handlePendingNavigation(_ destination: NavigationDestination?) {
        guard let destination else { return }

        // Append to the current tab's path
        switch selectedTab {
        case "home":
            homePath.append(destination)
        case "search":
            searchPath.append(destination)
        case TabBarItem.subscriptions.rawValue:
            subscriptionsPath.append(destination)
        case TabBarItem.channels.rawValue:
            channelsPath.append(destination)
        case TabBarItem.bookmarks.rawValue:
            bookmarksPath.append(destination)
        case TabBarItem.playlists.rawValue:
            playlistsPath.append(destination)
        case TabBarItem.history.rawValue:
            historyPath.append(destination)
        case TabBarItem.downloads.rawValue:
            downloadsPath.append(destination)
        case TabBarItem.sources.rawValue:
            sourcesPath.append(destination)
        case TabBarItem.settings.rawValue:
            settingsPath.append(destination)
        case TabBarItem.continueWatching.rawValue:
            continueWatchingPath.append(destination)
        default:
            // Fallback to home
            homePath.append(destination)
        }

        navigationCoordinator?.clearPendingNavigation()
    }
}

// MARK: - Preview

#Preview {
    CompactTabView()
        .appEnvironment(.preview)
}
#endif
