//
//  UnifiedTabView.swift
//  Yattee
//
//  Unified tab view with sidebar sections.
//  Uses TabSection to group navigation items and display user data (channels, playlists).
//  iOS 26.1+ gets additional features: bottom accessory mini player and tab bar minimize behavior.
//

import SwiftUI

// MARK: - iOS Tab Bar Helpers

#if os(iOS)
private extension View {
    @ViewBuilder
    func sidebarBottomBarPill() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }
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
                // iOS 27 stopped focusing the search field when the search tab is
                // selected; restore the iOS 26 behavior explicitly.
                .tabViewSearchActivation(.searchTabSelection)
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

#endif

// MARK: - iOS and macOS Implementation

#if os(iOS) || os(macOS)
/// Sidebar layout for iPad, the iPhone Duo inner screen and macOS: a
/// split view with a list sidebar. SwiftUI's sidebarAdaptable TabView never
/// shows a sidebar on iPhone idiom, so the split view is used on iOS too.
struct UnifiedTabView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let router: NavigationRouter

    // Zoom transition namespace (local to this tab view)
    @Namespace private var zoomTransition

    private var yatteeServerAuthHeader: String? {
        guard let server = appEnvironment?.instancesManager.enabledYatteeServerInstances.first else { return nil }
        return appEnvironment?.basicAuthCredentialsManager.basicAuthHeader(for: server)
    }

    #if os(iOS)
    private var zoomTransitionsEnabled: Bool {
        appEnvironment?.settingsManager.zoomTransitionsEnabled ?? true
    }
    #endif

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailForSelection
                #if os(iOS)
                .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayerInset }
                #endif
        }
        .zoomTransitionNamespace(zoomTransition)
        #if os(iOS)
        .zoomTransitionsEnabled(zoomTransitionsEnabled)
        #endif
        .onAppear {
            configureSidebarManager()
            router.applyStartupTabIfNeeded(settingsManager?.effectiveStartupTabForSidebar() ?? .home)
            ensureSelectionIsAvailable(visibleMainItems: visibleMainItems)
        }
        .onChange(of: router.selection) { _, _ in
            ensureSelectionIsAvailable(visibleMainItems: visibleMainItems)
        }
    }

    // MARK: - Visible Main Items

    private var visibleMainItems: [SidebarMainItem] {
        settingsManager?.visibleSidebarMainItems() ?? SidebarMainItem.defaultOrder
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            sidebarList

            if DataContextSwitcherVisibility.showsPickers(in: appEnvironment) {
                Divider()
                // The window has no toolbar of its own to hang this off, and the
                // sidebar is the one chrome every tab shares.
                DataContextSwitcherSettingsRow()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        #else
        sidebarList
            .safeAreaInset(edge: .bottom) {
                if DataContextSwitcherVisibility.showsPickers(in: appEnvironment) {
                    // The sidebar is the one surface every section shares, so
                    // the switcher lives here rather than on each screen's toolbar.
                    DataContextSwitcherSidebarRow()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .sidebarBottomBarPill()
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
        #endif
    }

    private var sidebarList: some View {
        // List selection is optional; deselecting keeps the current section.
        let selection = Binding<SidebarItem?>(
            get: { router.selection },
            set: { if let item = $0 { router.selection = item } }
        )

        return List(selection: selection) {
            ForEach(visibleMainItems) { item in
                sidebarRow(for: item)
            }

            if !sidebarManager.hasNoSources && (settingsManager?.sidebarSourcesEnabled ?? true) {
                Section(String(localized: "sidebar.section.sources")) {
                    ForEach(sidebarManager.sortedSourceItems) { item in
                        NavigationLink(value: item) {
                            Label(item.title, systemImage: item.systemImage)
                        }
                    }
                }
            }

            if !sidebarManager.channelItems.isEmpty && (settingsManager?.sidebarChannelsEnabled ?? true) {
                Section(String(localized: "sidebar.section.channels")) {
                    ForEach(sidebarManager.channelItems) { item in
                        NavigationLink(value: item) {
                            channelLabel(for: item)
                        }
                    }
                }
            }

            if !sidebarManager.playlistItems.isEmpty && (settingsManager?.sidebarPlaylistsEnabled ?? true) {
                Section(String(localized: "sidebar.section.playlists")) {
                    ForEach(sidebarManager.playlistItems) { item in
                        NavigationLink(value: item) {
                            playlistLabel(for: item)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sidebarRow(for item: SidebarMainItem) -> some View {
        let sidebarItem = item.sidebarItem
        NavigationLink(value: sidebarItem) {
            Label(sidebarItem.title, systemImage: sidebarItem.systemImage)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailForSelection: some View {
        let selection = router.selection
        switch selection {
        case .home:
            NavigationStack(path: router.path(for: .home)) {
                HomeView().withNavigationDestinations()
            }
        case .search:
            NavigationStack(path: router.path(for: .search)) {
                SearchView(searchText: Bindable(router).searchText).withNavigationDestinations()
            }
        case .subscriptionsFeed:
            NavigationStack(path: router.path(for: .subscriptionsFeed)) {
                SubscriptionsView().withNavigationDestinations()
            }
        case .bookmarks:
            NavigationStack(path: router.path(for: .bookmarks)) {
                BookmarksListView().withNavigationDestinations()
            }
        case .history:
            NavigationStack(path: router.path(for: .history)) {
                HistoryListView().withNavigationDestinations()
            }
        case .downloads:
            NavigationStack(path: router.path(for: .downloads)) {
                DownloadsView().withNavigationDestinations()
            }
        case .manageChannels:
            NavigationStack(path: router.path(for: .manageChannels)) {
                ManageChannelsView().withNavigationDestinations()
            }
        case .playlistsList:
            NavigationStack(path: router.path(for: .playlistsList)) {
                PlaylistsListView().withNavigationDestinations()
            }
        case .sources:
            NavigationStack(path: router.path(for: .sources)) {
                MediaSourcesView().withNavigationDestinations()
            }
        case .settings:
            NavigationStack(path: router.path(for: .settings)) {
                #if os(iOS)
                SettingsView(showCloseButton: false).withNavigationDestinations()
                #else
                SettingsView().withNavigationDestinations()
                #endif
            }
        case .openURL:
            NavigationStack(path: router.path(for: .openURL)) {
                OpenLinkView().withNavigationDestinations()
            }
        case .remoteControl:
            NavigationStack(path: router.path(for: .remoteControl)) {
                RemoteControlContentView(navigationStyle: .link)
                    .navigationTitle(String(localized: "remoteControl.title"))
                    .withNavigationDestinations()
            }
        case .continueWatching:
            NavigationStack(path: router.path(for: .continueWatching)) {
                ContinueWatchingView()
                    .withNavigationDestinations()
            }
        case .channel:
            channelContent(for: selection)
        case .playlist, .remotePlaylist:
            playlistContent(for: selection)
        case .mediaSource, .instance:
            sourceContent(for: selection)
        case .nowPlaying:
            EmptyView()
        }
    }

    private var settingsManager: SettingsManager? { appEnvironment?.settingsManager }

    #if os(iOS)
    /// The split view has no tab bar to host the mini player as a bottom
    /// accessory, so it takes the detail column's bottom safe area instead:
    /// floating content such as the subscriptions channel strip and the last
    /// rows of every list then clear it, as they clear the tab accessory.
    private var miniPlayerInset: some View {
        let hasActiveVideo = appEnvironment?.playerService.state.currentVideo != nil
        let isExpanded = appEnvironment?.navigationCoordinator.isPlayerExpanded ?? false

        return VStack(spacing: 0) {
            if hasActiveVideo && !isExpanded {
                MiniPlayerView()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    // Move-only transition (no opacity) prevents a thumbnail flash during collapse
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(response: 0.3), value: hasActiveVideo)
    }
    #endif
}

#Preview("Unified Tab View") {
    UnifiedTabView(router: NavigationRouter())
        .appEnvironment(.preview)
}
#endif

// MARK: - tvOS Implementation

#if os(tvOS)
struct UnifiedTabView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let router: NavigationRouter

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
        @Bindable var router = router

        TabView(selection: $router.selection) {
            mainTabs
            sidebarSections
        }
        .tabViewStyle(.sidebarAdaptable)
        .zoomTransitionNamespace(zoomTransition)
        .onAppear {
            configureSidebarManager()
            router.applyStartupTabIfNeeded(settingsManager?.effectiveStartupTabForSidebar() ?? .home)
            ensureSelectionIsAvailable(visibleMainItems: visibleMainItems)
        }
        .onChange(of: router.selection) { oldValue, _ in
            // Pop the previously-selected tab's stack to its root so its
            // pushed views don't linger after the user picks another item.
            // Before the remap, which may write the stack of `oldValue`.
            router.popToRoot(oldValue)
            ensureSelectionIsAvailable(visibleMainItems: visibleMainItems)
            // Force any pushed TVSidebarDetailContainer (used by Settings
            // sub-pages and similar detail screens) to dismiss. Without this,
            // tvOS's sidebarAdaptable TabView leaves the previously-pushed
            // detail visible until the user manually presses Menu.
            NotificationCenter.default.post(name: .yatteeTVForcePopDetail, object: nil)
        }
    }

    // MARK: - Visible Main Items

    private var visibleMainItems: [SidebarMainItem] {
        settingsManager?.visibleSidebarMainItems() ?? SidebarMainItem.defaultOrder
    }

    // MARK: - Tab Content Builders

    @TabContentBuilder<SidebarItem>
    private var mainTabs: some TabContent<SidebarItem> {
        // Now Playing (only shown when video is playing and player collapsed)
        if shouldShowNowPlaying,
           let currentVideo = appEnvironment?.playerService.state.currentVideo {
            Tab(value: SidebarItem.nowPlaying) {
                Color.clear
                    .onAppear {
                        appEnvironment?.navigationCoordinator.expandPlayer()
                        // Reset selection to prevent immediate re-trigger when player is collapsed
                        router.select(.home)
                    }
            } label: {
                Label("\(currentVideo.title)\n\(currentVideo.author.name)", systemImage: SidebarItem.nowPlaying.systemImage)
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
                NavigationStack(path: router.path(for: .search)) {
                    SearchView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.search.title, systemImage: SidebarItem.search.systemImage)
            }

        case .home:
            Tab(value: SidebarItem.home) {
                NavigationStack(path: router.path(for: .home)) {
                    HomeView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.home.title, systemImage: SidebarItem.home.systemImage)
            }

        case .subscriptions:
            Tab(value: SidebarItem.subscriptionsFeed) {
                NavigationStack(path: router.path(for: .subscriptionsFeed)) {
                    SubscriptionsView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.subscriptionsFeed.title, systemImage: SidebarItem.subscriptionsFeed.systemImage)
            }

        case .bookmarks:
            Tab(value: SidebarItem.bookmarks) {
                NavigationStack(path: router.path(for: .bookmarks)) {
                    BookmarksListView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.bookmarks.title, systemImage: SidebarItem.bookmarks.systemImage)
            }

        case .history:
            Tab(value: SidebarItem.history) {
                NavigationStack(path: router.path(for: .history)) {
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
                NavigationStack(path: router.path(for: .manageChannels)) {
                    ManageChannelsView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.manageChannels.title, systemImage: SidebarItem.manageChannels.systemImage)
            }

        case .playlists:
            Tab(value: SidebarItem.playlistsList) {
                NavigationStack(path: router.path(for: .playlistsList)) {
                    PlaylistsListView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.playlistsList.title, systemImage: SidebarItem.playlistsList.systemImage)
            }

        case .sources:
            Tab(value: SidebarItem.sources) {
                NavigationStack(path: router.path(for: .sources)) {
                    MediaSourcesView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.sources.title, systemImage: SidebarItem.sources.systemImage)
            }

        case .settings:
            Tab(value: SidebarItem.settings) {
                NavigationStack(path: router.path(for: .settings)) {
                    SettingsView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.settings.title, systemImage: SidebarItem.settings.systemImage)
            }

        case .openURL:
            Tab(value: SidebarItem.openURL) {
                NavigationStack(path: router.path(for: .openURL)) {
                    TVSidebarDetailContainer(
                        systemImage: SidebarItem.openURL.systemImage,
                        title: SidebarItem.openURL.title
                    ) {
                        OpenLinkView()
                    }
                    .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.openURL.title, systemImage: SidebarItem.openURL.systemImage)
            }

        case .remoteControl:
            Tab(value: SidebarItem.remoteControl) {
                NavigationStack(path: router.path(for: .remoteControl)) {
                    TVSidebarDetailContainer(
                        systemImage: SidebarItem.remoteControl.systemImage,
                        title: SidebarItem.remoteControl.title
                    ) {
                        RemoteControlContentView(navigationStyle: .link)
                    }
                    .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.remoteControl.title, systemImage: SidebarItem.remoteControl.systemImage)
            }

        case .continueWatching:
            Tab(value: SidebarItem.continueWatching) {
                NavigationStack(path: router.path(for: .continueWatching)) {
                    ContinueWatchingView()
                        .withNavigationDestinations()
                }
            } label: {
                Label(SidebarItem.continueWatching.title, systemImage: SidebarItem.continueWatching.systemImage)
            }
        }
    }

    @TabContentBuilder<SidebarItem>
    private var sidebarSections: some TabContent<SidebarItem> {
        // Sources Section (shows configured instances and media sources)
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
    UnifiedTabView(router: NavigationRouter())
        .appEnvironment(.preview)
}
#endif

// MARK: - Shared Helpers

extension UnifiedTabView {

    // MARK: - Computed Properties

    var sidebarManager: SidebarManager {
        router.sidebarManager
    }

    // MARK: - Configuration

    func configureSidebarManager() {
        guard let appEnvironment else { return }
        router.configureSidebarManagerIfNeeded(appEnvironment)
    }

    // MARK: - Layout Mapping

    /// Main items hidden from the sidebar by customization (or selected in the
    /// tab bar layout) are remapped onto a row that can host them.
    func ensureSelectionIsAvailable(visibleMainItems: [SidebarMainItem]) {
        let available = Set(visibleMainItems.map(\.sidebarItem))
        router.ensureSelectionIsAvailable(
            isAvailable: { item in
                switch item {
                case .channel, .playlist, .remotePlaylist, .mediaSource, .instance, .nowPlaying:
                    return true
                default:
                    return available.contains(item)
                }
            },
            instance: { id in appEnvironment?.instancesManager.enabledInstances.first { $0.id == id } }
        )
    }

    // MARK: - Channel Content & Labels

    @ViewBuilder
    func channelContent(for item: SidebarItem) -> some View {
        if case .channel(let channelID, _, let source) = item {
            NavigationStack(path: router.path(for: item)) {
                ChannelView(channelID: channelID, source: source)
                    .withNavigationDestinations()
            }
            .id(item.id)
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
        switch item {
        case .playlist(let id, _):
            NavigationStack(path: router.path(for: item)) {
                UnifiedPlaylistDetailView(source: .local(id))
                    .withNavigationDestinations()
            }
            .id(item.id)
        case .remotePlaylist(let id, let title, let accountID):
            NavigationStack(path: router.path(for: item)) {
                // No instance passed: the detail view resolves it from the
                // account, same as SidebarItem.navigationDestination().
                UnifiedPlaylistDetailView(source: .remote(id, instance: nil, title: title, accountID: accountID))
                    .withNavigationDestinations()
            }
            .id(item.id)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    func playlistLabel(for item: SidebarItem) -> some View {
        if item.isPlaylist {
            Label {
                Text(item.title)
            } icon: {
                SidebarPlaylistIcon(url: sidebarManager.thumbnailURL(for: item))
            }
        }
    }

    // MARK: - Media Source Content

    @ViewBuilder
    func mediaSourceContent(for item: SidebarItem) -> some View {
        if case .mediaSource(let id, _, _) = item,
           let source = appEnvironment?.mediaSourcesManager.source(byID: id) {
            NavigationStack(path: router.path(for: item)) {
                MediaBrowserView(source: source, path: "/")
                    .withNavigationDestinations()
            }
            .id(item.id)
        }
    }

    // MARK: - Instance Content

    @ViewBuilder
    func instanceContent(for item: SidebarItem) -> some View {
        if case .instance(let id, _, _) = item,
           let instance = appEnvironment?.instancesManager.enabledInstances.first(where: { $0.id == id }) {
            NavigationStack(path: router.path(for: item)) {
                InstanceBrowseView(instance: instance)
                    .withNavigationDestinations()
            }
            .id(item.id)
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
            mediaSourceContent(for: item)
        default:
            EmptyView()
        }
    }
}
