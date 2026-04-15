//
//  UnifiedTabView.swift
//  Yattee
//
//  Unified tab view with sidebar sections.
//  Uses TabSection to group navigation items and display user data (channels, playlists).
//  iOS 26.1+ gets additional features: bottom accessory mini player and tab bar minimize behavior.
//

import SwiftUI

// MARK: - iOS Implementation

#if os(iOS)
struct UnifiedTabView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Binding var selectedTab: AppTab

    // Sidebar manager for dynamic content
    @State private var sidebarManager = SidebarManager()

    // Navigation paths
    @State private var homePath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var channelPaths: [String: NavigationPath] = [:]
    @State private var playlistPaths: [UUID: NavigationPath] = [:]
    @State private var mediaSourcePaths: [UUID: NavigationPath] = [:]
    @State private var instancePaths: [UUID: NavigationPath] = [:]
    @State private var bookmarksPath = NavigationPath()
    @State private var historyPath = NavigationPath()
    @State private var downloadsPath = NavigationPath()
    @State private var subscriptionsFeedPath = NavigationPath()
    @State private var manageChannelsPath = NavigationPath()
    @State private var sourcesPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var openURLPath = NavigationPath()
    @State private var remoteControlPath = NavigationPath()

    // Current selection - initial value is a placeholder; actual startup tab is applied in onAppear
    @State private var selection: SidebarItem = .home
    @State private var hasAppliedStartupTab = false

    // Zoom transition namespace (local to this tab view)
    @Namespace private var zoomTransition

    private var shouldShowAccessory: Bool {
        guard let state = appEnvironment?.playerService.state else { return false }
        return state.currentVideo != nil
    }

    private var zoomTransitionsEnabled: Bool {
        appEnvironment?.settingsManager.zoomTransitionsEnabled ?? true
    }

    private var yatteeServerAuthHeader: String? {
        guard let server = appEnvironment?.instancesManager.enabledYatteeServerInstances.first else { return nil }
        return appEnvironment?.basicAuthCredentialsManager.basicAuthHeader(for: server)
    }

    var body: some View {
        TabView(selection: $selection) {
            mainTabs
            sidebarSections
        }
        .tabViewStyle(.sidebarAdaptable)
        .iOS26TabFeatures(shouldShowAccessory: shouldShowAccessory, settingsManager: appEnvironment?.settingsManager)
        .zoomTransitionNamespace(zoomTransition)
        .zoomTransitionsEnabled(zoomTransitionsEnabled)
        .onAppear {
            configureSidebarManager()
            applyStartupTabIfNeeded()
        }
        .onChange(of: navigationCoordinator?.pendingNavigation) { _, newValue in
            handlePendingNavigation(newValue)
        }
        .onChange(of: selectedTab) { _, newTab in
            selection = newTab.sidebarItem
        }
        .onChange(of: navigationCoordinator?.selectedSidebarItem) { _, newItem in
            guard let item = newItem else { return }
            selection = item
            navigationCoordinator?.selectedSidebarItem = nil
        }
    }

    /// Applies the configured startup tab on first appearance.
    private func applyStartupTabIfNeeded() {
        guard !hasAppliedStartupTab else { return }
        hasAppliedStartupTab = true

        let startupTab = settingsManager?.effectiveStartupTabForSidebar() ?? .home
        selection = startupTab.sidebarItem
    }

    // MARK: - Visible Main Items

    private var visibleMainItems: [SidebarMainItem] {
        settingsManager?.visibleSidebarMainItems() ?? SidebarMainItem.defaultOrder
    }

    // MARK: - Tab Builders

    @TabContentBuilder<SidebarItem>
    private var mainTabs: some TabContent<SidebarItem> {
        ForEach(visibleMainItems) { item in
            mainTab(for: item)
        }
    }

    @TabContentBuilder<SidebarItem>
    private func mainTab(for item: SidebarMainItem) -> some TabContent<SidebarItem> {
        switch item {
        case .search:
            Tab(value: SidebarItem.search, role: .search) {
                NavigationStack(path: $searchPath) {
                    SearchView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.search.title, systemImage: SidebarItem.search.systemImage)
            }

        case .home:
            Tab(value: SidebarItem.home) {
                NavigationStack(path: $homePath) {
                    HomeView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.home.title, systemImage: SidebarItem.home.systemImage)
            }

        case .subscriptions:
            Tab(value: SidebarItem.subscriptionsFeed) {
                NavigationStack(path: $subscriptionsFeedPath) {
                    SubscriptionsView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.subscriptionsFeed.title, systemImage: SidebarItem.subscriptionsFeed.systemImage)
            }

        case .bookmarks:
            Tab(value: SidebarItem.bookmarks) {
                NavigationStack(path: $bookmarksPath) {
                    BookmarksListView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.bookmarks.title, systemImage: SidebarItem.bookmarks.systemImage)
            }

        case .history:
            Tab(value: SidebarItem.history) {
                NavigationStack(path: $historyPath) {
                    HistoryListView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.history.title, systemImage: SidebarItem.history.systemImage)
            }

        case .downloads:
            Tab(value: SidebarItem.downloads) {
                NavigationStack(path: $downloadsPath) {
                    DownloadsView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.downloads.title, systemImage: SidebarItem.downloads.systemImage)
            }

        case .channels:
            Tab(value: SidebarItem.manageChannels) {
                NavigationStack(path: $manageChannelsPath) {
                    ManageChannelsView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.manageChannels.title, systemImage: SidebarItem.manageChannels.systemImage)
            }

        case .sources:
            Tab(value: SidebarItem.sources) {
                NavigationStack(path: $sourcesPath) {
                    MediaSourcesView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.sources.title, systemImage: SidebarItem.sources.systemImage)
            }

        case .settings:
            Tab(value: SidebarItem.settings) {
                NavigationStack(path: $settingsPath) {
                    SettingsView(showCloseButton: false)
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.settings.title, systemImage: SidebarItem.settings.systemImage)
            }

        case .openURL:
            Tab(value: SidebarItem.openURL) {
                NavigationStack(path: $openURLPath) {
                    OpenLinkView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.openURL.title, systemImage: SidebarItem.openURL.systemImage)
            }

        case .remoteControl:
            Tab(value: SidebarItem.remoteControl) {
                NavigationStack(path: $remoteControlPath) {
                    RemoteControlContentView(navigationStyle: .link)
                        .navigationTitle(String(localized: "remoteControl.title"))
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.remoteControl.title, systemImage: SidebarItem.remoteControl.systemImage)
            }
        }
    }

    @TabContentBuilder<SidebarItem>
    private var sidebarSections: some TabContent<SidebarItem> {
        // Unified Sources Section (sidebar only - shows instances + media sources)
        TabSection(String(localized: "sidebar.section.sources")) {
            ForEach(sidebarManager.sortedSourceItems) { item in
                Tab(value: item) {
                    sourceContent(for: item)
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                }
            }
        }
        .defaultVisibility(.hidden, for: .tabBar)
        .hidden(
            horizontalSizeClass == .compact ||
            sidebarManager.hasNoSources ||
            !(settingsManager?.sidebarSourcesEnabled ?? true)
        )

        // Channels Section (sidebar only - shows subscribed channels)
        TabSection(String(localized: "sidebar.section.channels")) {
            ForEach(sidebarManager.channelItems) { item in
                Tab(value: item) {
                    channelContent(for: item)
                } label: {
                    channelLabel(for: item)
                }
            }
        }
        .defaultVisibility(.hidden, for: .tabBar)
        .hidden(
            horizontalSizeClass == .compact ||
            sidebarManager.channelItems.isEmpty ||
            !(settingsManager?.sidebarChannelsEnabled ?? true)
        )

        // Playlists Section (sidebar only)
        TabSection(String(localized: "sidebar.section.playlists")) {
            ForEach(sidebarManager.playlistItems) { item in
                Tab(value: item) {
                    playlistContent(for: item)
                } label: {
                    playlistLabel(for: item)
                }
            }
        }
        .defaultVisibility(.hidden, for: .tabBar)
        .hidden(
            horizontalSizeClass == .compact ||
            sidebarManager.playlistItems.isEmpty ||
            !(settingsManager?.sidebarPlaylistsEnabled ?? true)
        )
    }

    private var settingsManager: SettingsManager? { appEnvironment?.settingsManager }
}

// iOS 26.1+ Tab Features
extension View {
    @ViewBuilder
    func iOS26TabFeatures(shouldShowAccessory: Bool, settingsManager: SettingsManager?) -> some View {
        if #available(iOS 26.1, *) {
            let behavior = settingsManager?.miniPlayerMinimizeBehavior.tabBarMinimizeBehavior ?? .onScrollDown
            self
                .tabViewBottomAccessory(isEnabled: shouldShowAccessory) {
                    MiniPlayerView(isTabAccessory: true)
                }
                .tabBarMinimizeBehavior(behavior)
        } else {
            self
        }
    }
}

@available(iOS 26, *)
extension MiniPlayerMinimizeBehavior {
    var tabBarMinimizeBehavior: TabBarMinimizeBehavior {
        switch self {
        case .onScrollDown:
            return .onScrollDown
        case .never:
            return .never
        }
    }
}

#Preview("Unified Tab View - iOS") {
    UnifiedTabView(selectedTab: .constant(.home))
        .appEnvironment(.preview)
}
#endif

// MARK: - macOS Implementation

#if os(macOS)
struct UnifiedTabView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    @Binding var selectedTab: AppTab

    // Sidebar manager for dynamic content
    @State private var sidebarManager = SidebarManager()

    // Navigation paths
    @State private var homePath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var channelPaths: [String: NavigationPath] = [:]
    @State private var playlistPaths: [UUID: NavigationPath] = [:]
    @State private var mediaSourcePaths: [UUID: NavigationPath] = [:]
    @State private var instancePaths: [UUID: NavigationPath] = [:]
    @State private var bookmarksPath = NavigationPath()
    @State private var historyPath = NavigationPath()
    @State private var downloadsPath = NavigationPath()
    @State private var subscriptionsFeedPath = NavigationPath()
    @State private var manageChannelsPath = NavigationPath()
    @State private var sourcesPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var openURLPath = NavigationPath()
    @State private var remoteControlPath = NavigationPath()

    // Current selection - initial value is a placeholder; actual startup tab is applied in onAppear
    @State private var selection: SidebarItem = .home
    @State private var hasAppliedStartupTab = false

    // Zoom transition namespace (local to this tab view)
    @Namespace private var zoomTransition

    private var yatteeServerAuthHeader: String? {
        guard let server = appEnvironment?.instancesManager.enabledYatteeServerInstances.first else { return nil }
        return appEnvironment?.basicAuthCredentialsManager.basicAuthHeader(for: server)
    }

    var body: some View {
        TabView(selection: $selection) {
            mainTabs
            sidebarSections
        }
        .tabViewStyle(.sidebarAdaptable)
        .zoomTransitionNamespace(zoomTransition)
        .onAppear {
            configureSidebarManager()
            applyStartupTabIfNeeded()
        }
        .onChange(of: navigationCoordinator?.pendingNavigation) { _, newValue in
            handlePendingNavigation(newValue)
        }
        .onChange(of: selectedTab) { _, newTab in
            selection = newTab.sidebarItem
        }
        .onChange(of: navigationCoordinator?.selectedSidebarItem) { _, newItem in
            guard let item = newItem else { return }
            selection = item
            navigationCoordinator?.selectedSidebarItem = nil
        }
    }

    /// Applies the configured startup tab on first appearance.
    private func applyStartupTabIfNeeded() {
        guard !hasAppliedStartupTab else { return }
        hasAppliedStartupTab = true

        let startupTab = settingsManager?.effectiveStartupTabForSidebar() ?? .home
        selection = startupTab.sidebarItem
    }

    // MARK: - Visible Main Items

    private var visibleMainItems: [SidebarMainItem] {
        settingsManager?.visibleSidebarMainItems() ?? SidebarMainItem.defaultOrder
    }

    // MARK: - Tab Builders

    @TabContentBuilder<SidebarItem>
    private var mainTabs: some TabContent<SidebarItem> {
        ForEach(visibleMainItems) { item in
            mainTab(for: item)
        }
    }

    @TabContentBuilder<SidebarItem>
    private func mainTab(for item: SidebarMainItem) -> some TabContent<SidebarItem> {
        switch item {
        case .search:
            Tab(value: SidebarItem.search, role: .search) {
                NavigationStack(path: $searchPath) {
                    SearchView().withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.search.title, systemImage: SidebarItem.search.systemImage)
            }

        case .home:
            Tab(value: SidebarItem.home) {
                NavigationStack(path: $homePath) {
                    HomeView().withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.home.title, systemImage: SidebarItem.home.systemImage)
            }

        case .subscriptions:
            Tab(value: SidebarItem.subscriptionsFeed) {
                NavigationStack(path: $subscriptionsFeedPath) {
                    SubscriptionsView().withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.subscriptionsFeed.title, systemImage: SidebarItem.subscriptionsFeed.systemImage)
            }

        case .bookmarks:
            Tab(value: SidebarItem.bookmarks) {
                NavigationStack(path: $bookmarksPath) {
                    BookmarksListView().withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.bookmarks.title, systemImage: SidebarItem.bookmarks.systemImage)
            }

        case .history:
            Tab(value: SidebarItem.history) {
                NavigationStack(path: $historyPath) {
                    HistoryListView().withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.history.title, systemImage: SidebarItem.history.systemImage)
            }

        case .downloads:
            Tab(value: SidebarItem.downloads) {
                NavigationStack(path: $downloadsPath) {
                    DownloadsView().withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.downloads.title, systemImage: SidebarItem.downloads.systemImage)
            }

        case .channels:
            Tab(value: SidebarItem.manageChannels) {
                NavigationStack(path: $manageChannelsPath) {
                    ManageChannelsView().withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.manageChannels.title, systemImage: SidebarItem.manageChannels.systemImage)
            }

        case .sources:
            Tab(value: SidebarItem.sources) {
                NavigationStack(path: $sourcesPath) {
                    MediaSourcesView().withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.sources.title, systemImage: SidebarItem.sources.systemImage)
            }

        case .settings:
            Tab(value: SidebarItem.settings) {
                NavigationStack(path: $settingsPath) {
                    SettingsView().withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.settings.title, systemImage: SidebarItem.settings.systemImage)
            }

        case .openURL:
            Tab(value: SidebarItem.openURL) {
                NavigationStack(path: $openURLPath) {
                    OpenLinkView().withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.openURL.title, systemImage: SidebarItem.openURL.systemImage)
            }

        case .remoteControl:
            Tab(value: SidebarItem.remoteControl) {
                NavigationStack(path: $remoteControlPath) {
                    RemoteControlContentView(navigationStyle: .link)
                        .navigationTitle(String(localized: "remoteControl.title"))
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.remoteControl.title, systemImage: SidebarItem.remoteControl.systemImage)
            }
        }
    }

    @TabContentBuilder<SidebarItem>
    private var sidebarSections: some TabContent<SidebarItem> {
        // Unified Sources Section (instances + media sources)
        if !sidebarManager.hasNoSources && (settingsManager?.sidebarSourcesEnabled ?? true) {
            TabSection(String(localized: "sidebar.section.sources")) {
                ForEach(sidebarManager.sortedSourceItems) { item in
                    Tab(value: item) {
                        sourceContent(for: item)
                    } label: {
                        Label(item.title, systemImage: item.systemImage)
                    }
                }
            }
        }

        if !sidebarManager.channelItems.isEmpty && (settingsManager?.sidebarChannelsEnabled ?? true) {
            TabSection(String(localized: "sidebar.section.channels")) {
                ForEach(sidebarManager.channelItems) { item in
                    Tab(value: item) {
                        channelContent(for: item)
                    } label: {
                        channelLabel(for: item)
                    }
                }
            }
        }

        if !sidebarManager.playlistItems.isEmpty && (settingsManager?.sidebarPlaylistsEnabled ?? true) {
            TabSection(String(localized: "sidebar.section.playlists")) {
                ForEach(sidebarManager.playlistItems) { item in
                    Tab(value: item) {
                        playlistContent(for: item)
                    } label: {
                        playlistLabel(for: item)
                    }
                }
            }
        }
    }

    private var settingsManager: SettingsManager? { appEnvironment?.settingsManager }
}

#Preview("Unified Tab View - macOS") {
    UnifiedTabView(selectedTab: .constant(.home))
        .appEnvironment(.preview)
}
#endif

// MARK: - tvOS Implementation

#if os(tvOS)
struct UnifiedTabView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    @Binding var selectedTab: AppTab

    // Sidebar manager for dynamic content
    @State private var sidebarManager = SidebarManager()

    // Navigation paths
    @State private var homePath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var channelPaths: [String: NavigationPath] = [:]
    @State private var playlistPaths: [UUID: NavigationPath] = [:]
    @State private var instancePaths: [UUID: NavigationPath] = [:]
    @State private var bookmarksPath = NavigationPath()
    @State private var historyPath = NavigationPath()
    @State private var subscriptionsFeedPath = NavigationPath()
    @State private var manageChannelsPath = NavigationPath()
    @State private var sourcesPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var openURLPath = NavigationPath()
    @State private var remoteControlPath = NavigationPath()

    // Current selection - initial value is a placeholder; actual startup tab is applied in onAppear
    @State private var selection: SidebarItem = .home
    @State private var hasAppliedStartupTab = false

    // Zoom transition namespace (local to this tab view)
    @Namespace private var zoomTransition

    private var shouldShowNowPlaying: Bool {
        guard let state = appEnvironment?.playerService.state else { return false }
        let isExpanded = appEnvironment?.navigationCoordinator.isPlayerExpanded ?? false
        return state.currentVideo != nil && !isExpanded
    }

    private var yatteeServerAuthHeader: String? {
        guard let server = appEnvironment?.instancesManager.enabledYatteeServerInstances.first else { return nil }
        return appEnvironment?.basicAuthCredentialsManager.basicAuthHeader(for: server)
    }

    var body: some View {
        TabView(selection: $selection) {
            mainTabs
            sidebarSections
        }
        .tabViewStyle(.sidebarAdaptable)
        .zoomTransitionNamespace(zoomTransition)
        .onAppear {
            configureSidebarManager()
            applyStartupTabIfNeeded()
        }
        .onChange(of: navigationCoordinator?.pendingNavigation) { _, newValue in
            handlePendingNavigation(newValue)
        }
    }

    /// Applies the configured startup tab on first appearance.
    private func applyStartupTabIfNeeded() {
        guard !hasAppliedStartupTab else { return }
        hasAppliedStartupTab = true

        let startupTab = settingsManager?.effectiveStartupTabForSidebar() ?? .home
        selection = startupTab.sidebarItem
    }

    // MARK: - Visible Main Items

    private var visibleMainItems: [SidebarMainItem] {
        settingsManager?.visibleSidebarMainItems() ?? SidebarMainItem.defaultOrder
    }

    // MARK: - Tab Content Builders

    @TabContentBuilder<SidebarItem>
    private var mainTabs: some TabContent<SidebarItem> {
        // Now Playing (only shown when video is playing and player collapsed)
        if shouldShowNowPlaying {
            Tab(value: SidebarItem.nowPlaying) {
                Color.clear
                    .onAppear {
                        appEnvironment?.navigationCoordinator.expandPlayer()
                        // Reset selection to prevent immediate re-trigger when player is collapsed
                        selection = .home
                    }
            } label: {
                Label(SidebarItem.nowPlaying.title, systemImage: SidebarItem.nowPlaying.systemImage)
            }
        }

        ForEach(visibleMainItems) { item in
            mainTab(for: item)
        }
    }

    @TabContentBuilder<SidebarItem>
    private func mainTab(for item: SidebarMainItem) -> some TabContent<SidebarItem> {
        switch item {
        case .search:
            Tab(value: SidebarItem.search, role: .search) {
                NavigationStack(path: $searchPath) {
                    SearchView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.search.title, systemImage: SidebarItem.search.systemImage)
            }

        case .home:
            Tab(value: SidebarItem.home) {
                NavigationStack(path: $homePath) {
                    HomeView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.home.title, systemImage: SidebarItem.home.systemImage)
            }

        case .subscriptions:
            Tab(value: SidebarItem.subscriptionsFeed) {
                NavigationStack(path: $subscriptionsFeedPath) {
                    SubscriptionsView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.subscriptionsFeed.title, systemImage: SidebarItem.subscriptionsFeed.systemImage)
            }

        case .bookmarks:
            Tab(value: SidebarItem.bookmarks) {
                NavigationStack(path: $bookmarksPath) {
                    BookmarksListView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.bookmarks.title, systemImage: SidebarItem.bookmarks.systemImage)
            }

        case .history:
            Tab(value: SidebarItem.history) {
                NavigationStack(path: $historyPath) {
                    HistoryListView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.history.title, systemImage: SidebarItem.history.systemImage)
            }

        case .downloads:
            // Downloads not available on tvOS
            // This case won't be reached due to isAvailableOnCurrentPlatform filtering
            Tab(value: SidebarItem.home) {
                EmptyView()
            }

        case .channels:
            Tab(value: SidebarItem.manageChannels) {
                NavigationStack(path: $manageChannelsPath) {
                    ManageChannelsView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.manageChannels.title, systemImage: SidebarItem.manageChannels.systemImage)
            }

        case .sources:
            Tab(value: SidebarItem.sources) {
                NavigationStack(path: $sourcesPath) {
                    MediaSourcesView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.sources.title, systemImage: SidebarItem.sources.systemImage)
            }

        case .settings:
            Tab(value: SidebarItem.settings) {
                NavigationStack(path: $settingsPath) {
                    SettingsView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.settings.title, systemImage: SidebarItem.settings.systemImage)
            }

        case .openURL:
            Tab(value: SidebarItem.openURL) {
                NavigationStack(path: $openURLPath) {
                    OpenLinkView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.openURL.title, systemImage: SidebarItem.openURL.systemImage)
            }

        case .remoteControl:
            Tab(value: SidebarItem.remoteControl) {
                NavigationStack(path: $remoteControlPath) {
                    RemoteControlContentView(navigationStyle: .link)
                        .navigationTitle(String(localized: "remoteControl.title"))
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.remoteControl.title, systemImage: SidebarItem.remoteControl.systemImage)
            }
        }
    }

    @TabContentBuilder<SidebarItem>
    private var sidebarSections: some TabContent<SidebarItem> {
        // Sources Section (shows configured instances)
        // Note: Media sources are only shown on iOS/macOS
        if !sidebarManager.sortedSourceItems.isEmpty && (settingsManager?.sidebarSourcesEnabled ?? true) {
            TabSection(String(localized: "sidebar.section.sources")) {
                ForEach(sidebarManager.sortedSourceItems) { item in
                    Tab(value: item) {
                        sourceContent(for: item)
                    } label: {
                        Label(item.title, systemImage: item.systemImage)
                    }
                }
            }
        }

        // Channels Section (shows subscribed channels)
        if !sidebarManager.channelItems.isEmpty && (settingsManager?.sidebarChannelsEnabled ?? true) {
            TabSection(String(localized: "sidebar.section.channels")) {
                ForEach(sidebarManager.channelItems) { item in
                    Tab(value: item) {
                        channelContent(for: item)
                    } label: {
                        channelLabel(for: item)
                    }
                }
            }
        }

        // Playlists Section
        if !sidebarManager.playlistItems.isEmpty && (settingsManager?.sidebarPlaylistsEnabled ?? true) {
            TabSection(String(localized: "sidebar.section.playlists")) {
                ForEach(sidebarManager.playlistItems) { item in
                    Tab(value: item) {
                        playlistContent(for: item)
                    } label: {
                        playlistLabel(for: item)
                    }
                }
            }
        }
    }

    private var settingsManager: SettingsManager? { appEnvironment?.settingsManager }
}

#Preview("Unified Tab View - tvOS") {
    UnifiedTabView(selectedTab: .constant(.home))
        .appEnvironment(.preview)
}
#endif

// MARK: - Shared Helpers

extension UnifiedTabView {

    // MARK: - Computed Properties

    var navigationCoordinator: NavigationCoordinator? {
        appEnvironment?.navigationCoordinator
    }

    // MARK: - Configuration

    func configureSidebarManager() {
        guard let appEnvironment else { return }
        sidebarManager.configure(
            dataManager: appEnvironment.dataManager,
            settingsManager: appEnvironment.settingsManager,
            mediaSourcesManager: appEnvironment.mediaSourcesManager,
            instancesManager: appEnvironment.instancesManager
        )
    }

    // MARK: - Navigation

    func handlePendingNavigation(_ destination: NavigationDestination?) {
        guard let destination else { return }
        switch selection {
        case .home:
            homePath.append(destination)
        case .search:
            searchPath.append(destination)
        case .channel(let channelID, _, _):
            channelPaths[channelID, default: NavigationPath()].append(destination)
        case .playlist(let id, _):
            playlistPaths[id, default: NavigationPath()].append(destination)
        case .mediaSource(let id, _, _):
            #if os(iOS) || os(macOS)
            mediaSourcePaths[id, default: NavigationPath()].append(destination)
            #endif
        case .instance(let id, _, _):
            instancePaths[id, default: NavigationPath()].append(destination)
        case .bookmarks:
            bookmarksPath.append(destination)
        case .history:
            historyPath.append(destination)
        case .downloads:
            #if os(iOS) || os(macOS)
            downloadsPath.append(destination)
            #endif
        case .subscriptionsFeed:
            subscriptionsFeedPath.append(destination)
        case .manageChannels:
            manageChannelsPath.append(destination)
        case .sources:
            sourcesPath.append(destination)
        case .settings:
            settingsPath.append(destination)
        case .nowPlaying:
            break // Now Playing is a root tab, not a push destination
        case .openURL:
            openURLPath.append(destination)
        case .remoteControl:
            remoteControlPath.append(destination)
        }
        navigationCoordinator?.clearPendingNavigation()
    }

    // MARK: - Path Bindings

    func channelPathBinding(for channelID: String) -> Binding<NavigationPath> {
        Binding(
            get: { channelPaths[channelID] ?? NavigationPath() },
            set: { channelPaths[channelID] = $0 }
        )
    }

    func playlistPathBinding(for id: UUID) -> Binding<NavigationPath> {
        Binding(
            get: { playlistPaths[id] ?? NavigationPath() },
            set: { playlistPaths[id] = $0 }
        )
    }

    #if os(iOS) || os(macOS)
    func mediaSourcePathBinding(for id: UUID) -> Binding<NavigationPath> {
        Binding(
            get: { mediaSourcePaths[id] ?? NavigationPath() },
            set: { mediaSourcePaths[id] = $0 }
        )
    }
    #endif

    func instancePathBinding(for id: UUID) -> Binding<NavigationPath> {
        Binding(
            get: { instancePaths[id] ?? NavigationPath() },
            set: { instancePaths[id] = $0 }
        )
    }

    // MARK: - Channel Content & Labels

    @ViewBuilder
    func channelContent(for item: SidebarItem) -> some View {
        if case .channel(let channelID, _, let source) = item {
            NavigationStack(path: channelPathBinding(for: channelID)) {
                ChannelView(channelID: channelID, source: source)
                    .withNavigationDestinations()
            }
        }
    }

    @ViewBuilder
    func channelLabel(for item: SidebarItem) -> some View {
        if case .channel(_, let name, _) = item {
            Label {
                Text(name)
            } icon: {
                SidebarChannelIcon(
                    url: sidebarManager.avatarURL(for: item),
                    name: name,
                    authHeader: yatteeServerAuthHeader
                )
            }
        }
    }

    // MARK: - Playlist Content & Labels

    @ViewBuilder
    func playlistContent(for item: SidebarItem) -> some View {
        if case .playlist(let id, _) = item {
            NavigationStack(path: playlistPathBinding(for: id)) {
                UnifiedPlaylistDetailView(source: .local(id))
                    .withNavigationDestinations()
            }
        }
    }

    @ViewBuilder
    func playlistLabel(for item: SidebarItem) -> some View {
        if case .playlist(_, let title) = item {
            Label {
                Text(title)
            } icon: {
                SidebarPlaylistIcon(url: sidebarManager.thumbnailURL(for: item))
            }
        }
    }

    // MARK: - Media Source Content

    #if os(iOS) || os(macOS)
    @ViewBuilder
    func mediaSourceContent(for item: SidebarItem) -> some View {
        if case .mediaSource(let id, _, _) = item,
           let source = appEnvironment?.mediaSourcesManager.source(byID: id) {
            NavigationStack(path: mediaSourcePathBinding(for: id)) {
                MediaBrowserView(source: source, path: "/")
                    .withNavigationDestinations()
            }
        }
    }
    #endif

    // MARK: - Instance Content

    @ViewBuilder
    func instanceContent(for item: SidebarItem) -> some View {
        if case .instance(let id, _, _) = item,
           let instance = appEnvironment?.instancesManager.enabledInstances.first(where: { $0.id == id }) {
            NavigationStack(path: instancePathBinding(for: id)) {
                InstanceBrowseView(instance: instance)
                    .withNavigationDestinations()
            }
        }
    }

    // MARK: - Unified Source Content

    /// Renders content for any source item (instance or media source).
    @ViewBuilder
    func sourceContent(for item: SidebarItem) -> some View {
        switch item {
        case .instance:
            instanceContent(for: item)
        case .mediaSource:
            #if os(iOS) || os(macOS)
            mediaSourceContent(for: item)
            #else
            EmptyView()
            #endif
        default:
            EmptyView()
        }
    }
}
