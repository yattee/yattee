//
//  HomeView.swift
//  Yattee
//
//  Home tab with shortcuts dashboard for Playlists, History, and Downloads.
//

import SwiftUI

struct HomeView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var sheetTransition
    @State private var playlists: [LocalPlaylist] = []
    @State private var bookmarksCount: Int = 0
    @State private var recentBookmarks: [Bookmark] = []
    @State private var continueWatchingCount: Int = 0
    @State private var recentContinueWatching: [WatchEntry] = []
    @State private var historyCount: Int = 0
    @State private var recentHistory: [WatchEntry] = []
    @State private var showingSettings = false
    @State private var showingOpenLink = false
    @State private var showingRemoteControl = false
    @State private var showingCustomizeHome = false
    @State private var channelsCount: Int = 0
    @State private var discoveredDevicesCount: Int = 0
    @State private var feedCache = SubscriptionFeedCache.shared

    private var dataManager: DataManager? { appEnvironment?.dataManager }
    private var settingsManager: SettingsManager? { appEnvironment?.settingsManager }

    #if !os(tvOS)
    private var downloadManager: DownloadManager? { appEnvironment?.downloadManager }
    #endif

    private var columns: [GridItem] {
        #if os(tvOS)
        [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 32)]
        #else
        [GridItem(.adaptive(minimum: 150), spacing: 16)]
        #endif
    }

    private var sectionItemsLimit: Int {
        settingsManager?.homeSectionItemsLimit ?? SettingsManager.defaultHomeSectionItemsLimit
    }

    /// Check if any shortcuts are visible
    private var hasVisibleShortcuts: Bool {
        guard let settings = settingsManager else { return true }
        return !settings.visibleShortcuts().isEmpty
    }

    /// The current layout for shortcuts (list or cards)
    private var shortcutLayout: HomeShortcutLayout {
        settingsManager?.homeShortcutLayout ?? .cards
    }

    /// The current layout for home sections (list or grid)
    private var sectionLayout: HomeSectionLayout {
        settingsManager?.homeSectionLayout ?? HomeSectionLayout.platformDefault
    }

    /// List style from centralized settings.
    private var listStyle: VideoListStyle {
        appEnvironment?.settingsManager.listStyle ?? .inset
    }

    var body: some View {
        mainContent
        #if !os(tvOS)
        .navigationTitle(String(localized: "tabs.home"))
        .navigationSubtitleIfAvailable(
            settingsManager?.incognitoModeEnabled == true
                ? String(localized: "home.incognitoMode.subtitle")
                : nil
        )
        .toolbarTitleDisplayMode(.inlineLarge)
        #endif
        .toolbar {
            #if !os(tvOS)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gear")
                }
                .accessibilityIdentifier("home.settingsButton")
                .accessibilityLabel(String(localized: "settings.title"))
                .liquidGlassTransitionSource(id: "homeSettings", in: sheetTransition)
            }
            #endif
        }
        #if !os(tvOS)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .liquidGlassSheetContent(sourceID: "homeSettings", in: sheetTransition)
        }
        .onChange(of: appEnvironment?.navigationCoordinator.dismissSettingsTrigger) {
            showingSettings = false
        }
        #endif
        .sheet(isPresented: $showingOpenLink) {
            OpenLinkSheet()
        }
        .sheet(isPresented: $showingRemoteControl) {
            RemoteDevicesSheet()
        }
        #if !os(tvOS)
        .sheet(isPresented: $showingCustomizeHome) {
            NavigationStack {
                HomeSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "common.done")) {
                                showingCustomizeHome = false
                            }
                        }
                    }
            }
        }
        #endif
        .onAppear {
            loadData()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                loadData()
            }
        }
        .task {
            await feedCache.loadFromDiskIfNeeded()
            await appEnvironment?.homeInstanceCache.loadFromDiskIfNeeded()
            await refreshHomeInstanceContent()
        }
        .onChange(of: appEnvironment?.navigationCoordinator.isPlayerExpanded) { _, isExpanded in
            // Refresh when player is collapsed
            if isExpanded == false {
                loadData()
            }
        }
        .onChange(of: appEnvironment?.navigationCoordinator.selectedTab) { _, newTab in
            if newTab == .home {
                loadData()
            }
        }
        .onChange(of: showingCustomizeHome) { _, isShowing in
            if !isShowing {
                loadData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarksDidChange)) { _ in
            loadBookmarksData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
            loadHistoryData()
            loadContinueWatchingData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .playlistsDidChange)) { _ in
            loadPlaylistsData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .subscriptionsDidChange)) { _ in
            loadChannelsData()
        }
    }

    // MARK: - Main Content

    #if os(tvOS)
    /// True on tvOS when no Home section would render content — prevents a focus trap
    /// on fresh installs where the detail pane would otherwise be completely empty.
    private var isHomeEmpty: Bool {
        let sections = settingsManager?.visibleSections() ?? HomeSectionItem.defaultOrder.filter { HomeSectionItem.defaultVisibility[$0] == true }
        for section in sections {
            switch section {
            case .continueWatching:
                if !recentContinueWatching.isEmpty { return false }
            case .feed:
                if !feedCache.videos.isEmpty { return false }
            case .bookmarks:
                if !recentBookmarks.isEmpty { return false }
            case .history:
                if !recentHistory.isEmpty { return false }
            case .downloads:
                break
            case .instanceContent, .mediaSource:
                return false
            }
        }
        return true
    }

    private var emptyHomeView: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Text(String(localized: "home.tvos.empty.title"))
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(String(localized: "home.tvos.empty.message"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                appEnvironment?.navigationCoordinator.selectedSidebarItem = .sources
            } label: {
                Label(String(localized: "home.tvos.empty.openSources"), systemImage: "externaldrive.connected.to.line.below")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif

    @ViewBuilder
    private var mainContent: some View {
        #if os(tvOS)
        if isHomeEmpty {
            emptyHomeView
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    homeContent
                }
            }
        }
        #else
        let backgroundStyle: ListBackgroundStyle = listStyle == .inset ? .grouped : .plain
        backgroundStyle.color
            .ignoresSafeArea()
            .overlay(
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Spacer().frame(height: 16)
                        homeContent
                    }
                }
            )
        #endif
    }

    // MARK: - Home Content

    @ViewBuilder
    private var homeContent: some View {
        #if !os(tvOS)
        if hasVisibleShortcuts {
            shortcutsSection
        }
        #endif

        ForEach(settingsManager?.visibleSections() ?? HomeSectionItem.defaultOrder.filter { HomeSectionItem.defaultVisibility[$0] == true }) { section in
            sectionView(for: section)
        }

        #if !os(tvOS)
        customizeButton
        #endif
    }

    // MARK: - Section Header Helper

    private func sectionHeader(title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Group {
            #if os(tvOS)
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)
            #else
            Button(action: action) {
                HStack(spacing: 4) {
                    Text(title)
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            #endif
        }
        .padding(.horizontal, listStyle == .inset ? 32 : 16)
        .padding(.top, 16)
        #if os(tvOS)
        .padding(.bottom, 24)
        #else
        .padding(.bottom, 8)
        #endif
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Customize Button

    #if !os(tvOS)
    private var customizeButton: some View {
        Button {
            showingCustomizeHome = true
        } label: {
            HStack(spacing: 6) {
                Spacer()
                Image(systemName: "gear")
                Text(String(localized: "home.customize"))
                    .fontWeight(.semibold)
                Spacer()
            }
        }
        .foregroundStyle(.secondary)
        .padding(.top, 16)
        .padding(.bottom, 32)
    }
    #endif

    // MARK: - Shortcuts Section

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if shortcutLayout == .list {
                VideoListContent(listStyle: listStyle) {
                    shortcutsList
                }
            } else {
                shortcutsCardContent
            }
        }
    }

    @ViewBuilder
    private var shortcutsCardContent: some View {
        if listStyle == .inset {
            VStack(spacing: 0) {
                shortcutsGrid
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
            }
            .background(ListBackgroundStyle.card.color)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        } else {
            shortcutsGrid
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    private var shortcutsGrid: some View {
        #if os(tvOS)
        let gridSpacing: CGFloat = 32
        #else
        let gridSpacing: CGFloat = 16
        #endif

        return LazyVGrid(columns: columns, spacing: gridSpacing) {
            ForEach(settingsManager?.visibleShortcuts() ?? HomeShortcutItem.defaultOrder) { shortcut in
                shortcutCardView(for: shortcut)
            }
        }
        #if os(iOS)
        // WORKAROUND: Prevent UICollectionView layout oscillation during iPad Stage Manager window resize.
        // The LazyVGrid inside a List section can cause 1pt height differences between layout passes,
        // triggering a feedback loop that crashes the app. Using geometryGroup() isolates the grid's
        // geometry calculations from the parent collection view's layout system.
        .geometryGroup()
        #endif
    }

    private var shortcutsList: some View {
        let shortcuts = settingsManager?.visibleShortcuts() ?? HomeShortcutItem.defaultOrder
        return ForEach(Array(shortcuts.enumerated()), id: \.element) { index, shortcut in
            VideoListRow(
                isLast: index == shortcuts.count - 1,
                rowStyle: .regular,
                listStyle: listStyle,
                contentWidth: 28
            ) {
                shortcutRowView(for: shortcut)
            }
        }
    }

    @ViewBuilder
    private func shortcutCardView(for shortcut: HomeShortcutItem) -> some View {
        switch shortcut {
        case .openURL:
            openURLShortcutCard
        case .remoteControl:
            remoteControlShortcutCard
        case .playlists:
            playlistsShortcutCard
        case .bookmarks:
            bookmarksShortcutCard
        case .continueWatching:
            continueWatchingShortcutCard
        case .history:
            historyShortcutCard
        case .downloads:
            #if !os(tvOS)
            downloadsShortcutCard
            #else
            EmptyView()
            #endif
        case .channels:
            channelsShortcutCard
        case .subscriptions:
            subscriptionsShortcutCard
        case .mediaSources:
            mediaSourcesShortcutCard
        case .instanceContent(let instanceID, let contentType):
            instanceContentShortcutCard(instanceID: instanceID, contentType: contentType)
        case .mediaSource(let sourceID):
            mediaSourceShortcutCard(sourceID: sourceID)
        }
    }

    @ViewBuilder
    private func shortcutRowView(for shortcut: HomeShortcutItem) -> some View {
        switch shortcut {
        case .openURL:
            openURLShortcutRow
        case .remoteControl:
            remoteControlShortcutRow
        case .playlists:
            playlistsShortcutRow
        case .bookmarks:
            bookmarksShortcutRow
        case .continueWatching:
            continueWatchingShortcutRow
        case .history:
            historyShortcutRow
        case .downloads:
            #if !os(tvOS)
            downloadsShortcutRow
            #else
            EmptyView()
            #endif
        case .channels:
            channelsShortcutRow
        case .subscriptions:
            subscriptionsShortcutRow
        case .mediaSources:
            mediaSourcesShortcutRow
        case .instanceContent(let instanceID, let contentType):
            instanceContentShortcutRow(instanceID: instanceID, contentType: contentType)
        case .mediaSource(let sourceID):
            mediaSourceShortcutRow(sourceID: sourceID)
        }
    }

    // MARK: - Shortcut Card Views

    private var openURLShortcutCard: some View {
        Button {
            showingOpenLink = true
        } label: {
            HomeShortcutCardView(
                icon: "link",
                title: String(localized: "home.shortcut.openURL"),
                count: 0,
                subtitle: ""
            )
        }
        #if os(tvOS)
        .buttonStyle(TVHomeCardButtonStyle())
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityIdentifier("home.shortcut.openURL")
    }

    private var remoteControlShortcutCard: some View {
        let isHosting = appEnvironment?.localNetworkService.isHosting ?? false

        return Button {
            showingRemoteControl = true
        } label: {
            HomeShortcutCardView(
                icon: "antenna.radiowaves.left.and.right",
                title: String(localized: "home.shortcut.remoteControl"),
                count: discoveredDevicesCount,
                subtitle: "",
                statusIndicator: Circle()
                    .fill(isHosting ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            )
        }
        #if os(tvOS)
        .buttonStyle(TVHomeCardButtonStyle())
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityIdentifier("home.shortcut.remoteControl")
    }

    private var playlistsShortcutCard: some View {
        Button {
            appEnvironment?.navigationCoordinator.navigate(to: .playlists)
        } label: {
            HomeShortcutCardView(
                icon: "list.bullet.rectangle",
                title: String(localized: "home.playlists.title"),
                count: playlists.count,
                subtitle: formatCount(playlists.count, singular: "home.count.playlist", plural: "home.count.playlists")
            )
        }
        #if os(tvOS)
        .buttonStyle(TVHomeCardButtonStyle())
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityIdentifier("home.shortcut.playlists")
    }

    private var bookmarksShortcutCard: some View {
        Button {
            appEnvironment?.navigationCoordinator.navigate(to: .bookmarks)
        } label: {
            HomeShortcutCardView(
                icon: "bookmark",
                title: String(localized: "home.bookmarks.title"),
                count: bookmarksCount,
                subtitle: formatCount(bookmarksCount, singular: "home.count.bookmark", plural: "home.count.bookmarks")
            )
        }
        #if os(tvOS)
        .buttonStyle(TVHomeCardButtonStyle())
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityIdentifier("home.shortcut.bookmarks")
    }

    private var continueWatchingShortcutCard: some View {
        Button {
            appEnvironment?.navigationCoordinator.navigate(to: .continueWatching)
        } label: {
            HomeShortcutCardView(
                icon: "play.circle",
                title: String(localized: "home.shortcut.continueWatching"),
                count: continueWatchingCount,
                subtitle: formatCount(continueWatchingCount, singular: "home.count.video", plural: "home.count.videos")
            )
        }
        #if os(tvOS)
        .buttonStyle(TVHomeCardButtonStyle())
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityIdentifier("home.shortcut.continueWatching")
    }

    private var historyShortcutCard: some View {
        Button {
            appEnvironment?.navigationCoordinator.navigate(to: .history)
        } label: {
            HomeShortcutCardView(
                icon: "clock",
                title: String(localized: "home.history.title"),
                count: historyCount,
                subtitle: formatCount(historyCount, singular: "home.count.video", plural: "home.count.videos")
            )
        }
        #if os(tvOS)
        .buttonStyle(TVHomeCardButtonStyle())
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityIdentifier("home.shortcut.history")
    }

    #if !os(tvOS)
    private var downloadsShortcutCard: some View {
        let count = downloadManager?.completedDownloads.count ?? 0
        return Button {
            appEnvironment?.navigationCoordinator.navigate(to: .downloads)
        } label: {
            HomeShortcutCardView(
                icon: "arrow.down.circle",
                title: String(localized: "home.downloads.title"),
                count: count,
                subtitle: formatCount(count, singular: "home.count.video", plural: "home.count.videos")
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.shortcut.downloads")
    }
    #endif

    private var channelsShortcutCard: some View {
        Button {
            appEnvironment?.navigationCoordinator.navigate(to: .manageChannels)
        } label: {
            HomeShortcutCardView(
                icon: "person.2",
                title: String(localized: "home.channels.title"),
                count: channelsCount,
                subtitle: formatCount(channelsCount, singular: "home.count.channel", plural: "home.count.channels")
            )
        }
        #if os(tvOS)
        .buttonStyle(TVHomeCardButtonStyle())
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityIdentifier("home.shortcut.channels")
    }

    private var subscriptionsShortcutCard: some View {
        Button {
            appEnvironment?.navigationCoordinator.navigate(to: .subscriptionsFeed)
        } label: {
            HomeShortcutCardView(
                icon: "play.square.stack",
                title: String(localized: "home.subscriptions.title"),
                count: 0,
                subtitle: String(localized: "home.subscriptions.subtitle")
            )
        }
        #if os(tvOS)
        .buttonStyle(TVHomeCardButtonStyle())
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityIdentifier("home.shortcut.subscriptions")
    }

    private var mediaSourcesShortcutCard: some View {
        let mediaSourcesCount = appEnvironment?.mediaSourcesManager.enabledSources.count ?? 0
        let instancesCount = appEnvironment?.instancesManager.instances.count ?? 0
        let count = mediaSourcesCount + instancesCount
        return Button {
            appEnvironment?.navigationCoordinator.navigate(to: .mediaSources)
        } label: {
            HomeShortcutCardView(
                icon: "externaldrive.connected.to.line.below",
                title: "Sources",
                count: count,
                subtitle: count == 1 ? "1 source" : "\(count) sources"
            )
        }
        #if os(tvOS)
        .buttonStyle(TVHomeCardButtonStyle())
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityIdentifier("home.shortcut.mediaSources")
    }

    @ViewBuilder
    private func instanceContentShortcutCard(instanceID: UUID, contentType: InstanceContentType) -> some View {
        if let instance = appEnvironment?.instancesManager.instances.first(where: { $0.id == instanceID }),
           instance.isEnabled {
            Button {
                // Navigate to InstanceBrowseView with the correct tab selected
                appEnvironment?.navigationCoordinator.navigate(to: .instanceBrowse(instance, initialTab: contentType.toBrowseTab()))
            } label: {
                HomeShortcutCardView(
                    icon: contentType.icon,
                    title: contentType.localizedTitle,
                    count: 0,
                    subtitle: instance.displayName
                )
            }
            #if os(tvOS)
            .buttonStyle(TVHomeCardButtonStyle())
            #else
            .buttonStyle(.plain)
            #endif
        }
    }

    @ViewBuilder
    private func mediaSourceShortcutCard(sourceID: UUID) -> some View {
        if let source = appEnvironment?.mediaSourcesManager.sources.first(where: { $0.id == sourceID }),
           source.isEnabled {
            Button {
                // Navigate to MediaBrowserView at root path
                appEnvironment?.navigationCoordinator.navigate(to: .mediaBrowser(source, path: "/"))
            } label: {
                HomeShortcutCardView(
                    icon: source.type.systemImage,
                    title: source.name,
                    count: 0,
                    subtitle: source.type.displayName
                )
            }
            #if os(tvOS)
            .buttonStyle(TVHomeCardButtonStyle())
            #else
            .buttonStyle(.plain)
            #endif
        }
    }

    // MARK: - Shortcut Row Views

    private var openURLShortcutRow: some View {
        Button {
            showingOpenLink = true
        } label: {
            HomeShortcutRowView(
                icon: "link",
                title: String(localized: "home.shortcut.openURL"),
                subtitle: ""
            )
        }
        .buttonStyle(.plain)
    }

    private var remoteControlShortcutRow: some View {
        let isHosting = appEnvironment?.localNetworkService.isHosting ?? false

        return Button {
            showingRemoteControl = true
        } label: {
            HomeShortcutRowView(
                icon: "antenna.radiowaves.left.and.right",
                title: String(localized: "home.shortcut.remoteControl"),
                subtitle: "",
                statusIndicator: Circle()
                    .fill(isHosting ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            )
        }
        .buttonStyle(.plain)
    }

    private var playlistsShortcutRow: some View {
        Button {
            appEnvironment?.navigationCoordinator.navigate(to: .playlists)
        } label: {
            HomeShortcutRowView(
                icon: "list.bullet.rectangle",
                title: String(localized: "home.playlists.title"),
                subtitle: formatCount(playlists.count, singular: "home.count.playlist", plural: "home.count.playlists")
            )
        }
        .buttonStyle(.plain)
    }

    private var bookmarksShortcutRow: some View {
        Button {
            appEnvironment?.navigationCoordinator.navigate(to: .bookmarks)
        } label: {
            HomeShortcutRowView(
                icon: "bookmark.fill",
                title: String(localized: "home.bookmarks.title"),
                subtitle: formatCount(bookmarksCount, singular: "home.count.bookmark", plural: "home.count.bookmarks")
            )
        }
        .buttonStyle(.plain)
    }

    private var continueWatchingShortcutRow: some View {
        Button {
            appEnvironment?.navigationCoordinator.navigate(to: .continueWatching)
        } label: {
            HomeShortcutRowView(
                icon: "play.circle",
                title: String(localized: "home.shortcut.continueWatching"),
                subtitle: formatCount(continueWatchingCount, singular: "home.count.video", plural: "home.count.videos")
            )
        }
        .buttonStyle(.plain)
    }

    private var historyShortcutRow: some View {
        Button {
            appEnvironment?.navigationCoordinator.navigate(to: .history)
        } label: {
            HomeShortcutRowView(
                icon: "clock",
                title: String(localized: "home.history.title"),
                subtitle: formatCount(historyCount, singular: "home.count.video", plural: "home.count.videos")
            )
        }
        .buttonStyle(.plain)
    }

    #if !os(tvOS)
    private var downloadsShortcutRow: some View {
        let count = downloadManager?.completedDownloads.count ?? 0
        return Button {
            appEnvironment?.navigationCoordinator.navigate(to: .downloads)
        } label: {
            HomeShortcutRowView(
                icon: "arrow.down.circle",
                title: String(localized: "home.downloads.title"),
                subtitle: formatCount(count, singular: "home.count.video", plural: "home.count.videos")
            )
        }
        .buttonStyle(.plain)
    }
    #endif

    private var channelsShortcutRow: some View {
        Button {
            appEnvironment?.navigationCoordinator.navigate(to: .manageChannels)
        } label: {
            HomeShortcutRowView(
                icon: "person.2",
                title: String(localized: "home.channels.title"),
                subtitle: formatCount(channelsCount, singular: "home.count.channel", plural: "home.count.channels")
            )
        }
        .buttonStyle(.plain)
    }

    private var subscriptionsShortcutRow: some View {
        Button {
            appEnvironment?.navigationCoordinator.navigate(to: .subscriptionsFeed)
        } label: {
            HomeShortcutRowView(
                icon: "play.rectangle.on.rectangle",
                title: String(localized: "home.subscriptions.title"),
                subtitle: String(localized: "home.subscriptions.subtitle")
            )
        }
        .buttonStyle(.plain)
    }

    private var mediaSourcesShortcutRow: some View {
        let mediaSourcesCount = appEnvironment?.mediaSourcesManager.enabledSources.count ?? 0
        let instancesCount = appEnvironment?.instancesManager.instances.count ?? 0
        let count = mediaSourcesCount + instancesCount
        return Button {
            appEnvironment?.navigationCoordinator.navigate(to: .mediaSources)
        } label: {
            HomeShortcutRowView(
                icon: "externaldrive.connected.to.line.below",
                title: "Sources",
                subtitle: count == 1 ? "1 source" : "\(count) sources"
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func instanceContentShortcutRow(instanceID: UUID, contentType: InstanceContentType) -> some View {
        if let instance = appEnvironment?.instancesManager.instances.first(where: { $0.id == instanceID }),
           instance.isEnabled {
            Button {
                appEnvironment?.navigationCoordinator.navigate(to: .instanceBrowse(instance, initialTab: contentType.toBrowseTab()))
            } label: {
                HomeShortcutRowView(
                    icon: contentType.icon,
                    title: contentType.localizedTitle,
                    subtitle: instance.displayName
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func mediaSourceShortcutRow(sourceID: UUID) -> some View {
        if let source = appEnvironment?.mediaSourcesManager.sources.first(where: { $0.id == sourceID }),
           source.isEnabled {
            Button {
                appEnvironment?.navigationCoordinator.navigate(to: .mediaBrowser(source, path: "/"))
            } label: {
                HomeShortcutRowView(
                    icon: source.type.systemImage,
                    title: source.name,
                    subtitle: source.type.displayName
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// Formats a count with compact notation and proper singular/plural form.
    private func formatCount(_ count: Int, singular: String.LocalizationValue, plural: String.LocalizationValue) -> String {
        let formattedCount = CountFormatter.compact(count)
        let key = count == 1 ? singular : plural
        return String(localized: "\(formattedCount) \(String(localized: key))")
    }
    
    // MARK: - Queue Support
    
    /// Queue source for recent bookmarks section
    private var recentBookmarksQueueSource: QueueSource { .manual }
    
    /// Queue source for continue watching section
    private var continueWatchingQueueSource: QueueSource { .manual }
    
    /// Queue source for recent history section
    private var recentHistoryQueueSource: QueueSource { .manual }
    
    /// Queue source for feed section
    private var feedQueueSource: QueueSource { .subscriptions(continuation: nil) }
    
    /// Returns queue source for instance content
    private func instanceQueueSource(instanceID: UUID, contentType: InstanceContentType) -> QueueSource {
        .manual
    }
    
    /// Stub callback for recent bookmarks queue continuation
    @Sendable
    private func loadMoreRecentBookmarksCallback() async throws -> ([Video], String?) {
        return ([], nil)  // No pagination for Home sections
    }
    
    /// Stub callback for continue watching queue continuation
    @Sendable
    private func loadMoreContinueWatchingCallback() async throws -> ([Video], String?) {
        return ([], nil)  // No pagination for Home sections
    }
    
    /// Stub callback for recent history queue continuation
    @Sendable
    private func loadMoreRecentHistoryCallback() async throws -> ([Video], String?) {
        return ([], nil)  // No pagination for Home sections
    }
    
    /// Stub callback for feed queue continuation
    @Sendable
    private func loadMoreFeedCallback() async throws -> ([Video], String?) {
        return ([], nil)  // Feed section doesn't paginate
    }
    
    /// Stub callback for instance content queue continuation
    @Sendable
    private func loadMoreInstanceContentCallback() async throws -> ([Video], String?) {
        return ([], nil)  // No pagination for Home sections
    }
    
    #if !os(tvOS)
    /// Stub callback for recent downloads queue continuation
    @Sendable
    private func loadMoreRecentDownloadsCallback() async throws -> ([Video], String?) {
        return ([], nil)  // No pagination for Home sections
    }
    #endif

    // MARK: - Sections

    @ViewBuilder
    private func sectionView(for section: HomeSectionItem) -> some View {
        switch section {
        case .continueWatching:
            if !recentContinueWatching.isEmpty {
                continueWatchingSection
            }
        case .feed:
            if !feedCache.videos.isEmpty {
                feedSection
            }
        case .bookmarks:
            if !recentBookmarks.isEmpty {
                bookmarksSection
            }
        case .history:
            if !recentHistory.isEmpty {
                historySection
            }
        case .downloads:
            #if !os(tvOS)
            if let downloads = downloadManager?.completedDownloads, !downloads.isEmpty {
                downloadsSection(downloads: downloads)
            }
            #else
            EmptyView()
            #endif
        case .instanceContent(let instanceID, let contentType):
            instanceContentSection(instanceID: instanceID, contentType: contentType)
        case .mediaSource(let sourceID):
            mediaSourceSection(sourceID: sourceID)
        }
    }

    private var continueWatchingSection: some View {
        let limitedEntries = Array(recentContinueWatching.prefix(sectionItemsLimit))
        let videoList = limitedEntries.map { $0.toVideo() }

        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "home.section.continueWatching") {
                appEnvironment?.navigationCoordinator.navigate(to: .continueWatching)
            }

            if sectionLayout == .grid {
                HomeHorizontalCards(
                    videos: videoList,
                    queueSource: continueWatchingQueueSource,
                    sourceLabel: String(localized: "queue.source.continueWatching"),
                    loadMoreVideos: loadMoreContinueWatchingCallback
                )
            } else {
            VideoListContent(listStyle: listStyle) {
                ForEach(Array(limitedEntries.enumerated()), id: \.element.videoIdentifier) { index, entry in
                    VideoListRow(
                        isLast: index == limitedEntries.count - 1,
                        rowStyle: .regular,
                        listStyle: listStyle
                    ) {
                        WatchEntryRowView(
                            entry: entry,
                            onRemove: {
                                dataManager?.removeFromHistory(videoID: entry.videoID)
                                loadData()
                            },
                            queueSource: continueWatchingQueueSource,
                            sourceLabel: String(localized: "queue.source.continueWatching"),
                            videoList: videoList,
                            videoIndex: index,
                            loadMoreVideos: loadMoreContinueWatchingCallback
                        )
                    }
                    #if !os(tvOS)
                    .videoSwipeActions(
                        video: videoList[index],
                        fixedActions: [
                            SwipeAction(
                                symbolImage: "trash.fill",
                                tint: .white,
                                background: .red
                            ) { reset in
                                dataManager?.removeFromHistory(videoID: entry.videoID)
                                loadData()
                                reset()
                            }
                        ]
                    )
                    #endif
                }
            }
            }
        }
    }

    private var feedSection: some View {
        let limitedVideos = Array(feedCache.videos.prefix(sectionItemsLimit))

        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "home.recentFeed.title") {
                appEnvironment?.navigationCoordinator.navigate(to: .subscriptionsFeed)
            }

            if sectionLayout == .grid {
                HomeHorizontalCards(
                    videos: limitedVideos,
                    queueSource: feedQueueSource,
                    sourceLabel: String(localized: "queue.source.subscriptions"),
                    loadMoreVideos: loadMoreFeedCallback
                )
            } else {
                VideoListContent(listStyle: listStyle) {
                    ForEach(Array(limitedVideos.enumerated()), id: \.element.id) { index, video in
                        VideoListRow(
                            isLast: index == limitedVideos.count - 1,
                            rowStyle: .regular,
                            listStyle: listStyle
                        ) {
                            VideoRowView(video: video, style: .regular)
                                .tappableVideo(
                                    video,
                                    queueSource: feedQueueSource,
                                    sourceLabel: String(localized: "queue.source.subscriptions"),
                                    videoList: limitedVideos,
                                    videoIndex: index,
                                    loadMoreVideos: loadMoreFeedCallback
                                )
                        }
                        #if !os(tvOS)
                        .videoSwipeActions(video: video)
                        #endif
                    }
                }
            }
        }
    }

    private var bookmarksSection: some View {
        let limitedBookmarks = Array(recentBookmarks.prefix(sectionItemsLimit))
        let videoList = limitedBookmarks.map { $0.toVideo() }

        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "home.recentBookmarks.title") {
                appEnvironment?.navigationCoordinator.navigate(to: .bookmarks)
            }

            if sectionLayout == .grid {
                HomeHorizontalCards(
                    videos: videoList,
                    queueSource: recentBookmarksQueueSource,
                    sourceLabel: String(localized: "queue.source.bookmarks"),
                    loadMoreVideos: loadMoreRecentBookmarksCallback
                )
            } else {
            VideoListContent(listStyle: listStyle) {
                ForEach(Array(limitedBookmarks.enumerated()), id: \.element.videoID) { index, bookmark in
                    VideoListRow(
                        isLast: index == limitedBookmarks.count - 1,
                        rowStyle: .regular,
                        listStyle: listStyle
                    ) {
                        BookmarkRowView(
                            bookmark: bookmark,
                            onRemove: {
                                dataManager?.removeBookmark(for: bookmark.videoID)
                                loadData()
                            },
                            queueSource: recentBookmarksQueueSource,
                            sourceLabel: String(localized: "queue.source.bookmarks"),
                            videoList: videoList,
                            videoIndex: index,
                            loadMoreVideos: loadMoreRecentBookmarksCallback
                        )
                    }
                    #if !os(tvOS)
                    .videoSwipeActions(
                        video: videoList[index],
                        fixedActions: [
                            SwipeAction(
                                symbolImage: "trash.fill",
                                tint: .white,
                                background: .red
                            ) { reset in
                                dataManager?.removeBookmark(for: bookmark.videoID)
                                loadData()
                                reset()
                            }
                        ]
                    )
                    #endif
                }
            }
            }
        }
    }

    private var historySection: some View {
        let limitedHistory = Array(recentHistory.prefix(sectionItemsLimit))
        let videoList = limitedHistory.map { $0.toVideo() }

        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "home.recentHistory.title") {
                appEnvironment?.navigationCoordinator.navigate(to: .history)
            }

            if sectionLayout == .grid {
                HomeHorizontalCards(
                    videos: videoList,
                    queueSource: recentHistoryQueueSource,
                    sourceLabel: String(localized: "queue.source.history"),
                    loadMoreVideos: loadMoreRecentHistoryCallback
                )
            } else {
            VideoListContent(listStyle: listStyle) {
                ForEach(Array(limitedHistory.enumerated()), id: \.element.videoID) { index, entry in
                    VideoListRow(
                        isLast: index == limitedHistory.count - 1,
                        rowStyle: .regular,
                        listStyle: listStyle
                    ) {
                        WatchEntryRowView(
                            entry: entry,
                            onRemove: {
                                dataManager?.removeFromHistory(videoID: entry.videoID)
                                loadData()
                            },
                            queueSource: recentHistoryQueueSource,
                            sourceLabel: String(localized: "queue.source.history"),
                            videoList: videoList,
                            videoIndex: index,
                            loadMoreVideos: loadMoreRecentHistoryCallback
                        )
                    }
                    #if !os(tvOS)
                    .videoSwipeActions(
                        video: videoList[index],
                        fixedActions: [
                            SwipeAction(
                                symbolImage: "trash.fill",
                                tint: .white,
                                background: .red
                            ) { reset in
                                dataManager?.removeFromHistory(videoID: entry.videoID)
                                loadData()
                                reset()
                            }
                        ]
                    )
                    #endif
                }
            }
            }
        }
    }

    #if !os(tvOS)
    private func downloadsSection(downloads: [Download]) -> some View {
        let limitedDownloads = Array(downloads.prefix(sectionItemsLimit))
        // Use toVideo() instead of videoAndStream() to avoid O(n²) file I/O on main thread
        // Downloads are looked up by video.id at playback time in PlayerService.playPreferringDownloaded()
        let downloadsDir = downloadManager?.downloadsDirectory()
        let videoList = limitedDownloads.map { $0.toVideo(downloadsDirectory: downloadsDir) }

        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "home.recentDownloads.title") {
                appEnvironment?.navigationCoordinator.navigate(to: .downloads)
            }

            if sectionLayout == .grid {
                HomeHorizontalCards(
                    videos: videoList,
                    queueSource: .manual,
                    sourceLabel: String(localized: "queue.source.downloads"),
                    loadMoreVideos: loadMoreRecentDownloadsCallback
                )
            } else {
            VideoListContent(listStyle: listStyle) {
                ForEach(Array(limitedDownloads.enumerated()), id: \.element.id) { index, download in
                    VideoListRow(
                        isLast: index == limitedDownloads.count - 1,
                        rowStyle: .regular,
                        listStyle: listStyle
                    ) {
                        DownloadRowView(
                            download: download,
                            isActive: false,
                            onDelete: {
                                Task {
                                    await downloadManager?.delete(download)
                                }
                            },
                            queueSource: .manual,
                            sourceLabel: String(localized: "queue.source.downloads"),
                            videoList: videoList,
                            videoIndex: index,
                            loadMoreVideos: loadMoreRecentDownloadsCallback
                        )
                    }
                    .videoSwipeActions(
                        video: videoList[index],
                        fixedActions: [
                            SwipeAction(
                                symbolImage: "trash.fill",
                                tint: .white,
                                background: .red
                            ) { reset in
                                Task {
                                    await downloadManager?.delete(download)
                                }
                                reset()
                            }
                        ]
                    )
                }
            }
            }
        }
    }
    #endif

    @ViewBuilder
    private func instanceContentSection(instanceID: UUID, contentType: InstanceContentType) -> some View {
        // Only show if instance is enabled and has cached videos
        if let instance = appEnvironment?.instancesManager.instances.first(where: { $0.id == instanceID }),
           instance.isEnabled,
           let videos = appEnvironment?.homeInstanceCache.videos(for: instanceID, contentType: contentType),
           !videos.isEmpty {
            let limitedVideos = Array(videos.prefix(sectionItemsLimit))

            VStack(alignment: .leading, spacing: 0) {
                Group {
                    #if os(tvOS)
                    Text(verbatim: "\(contentType.localizedTitle) - \(instance.displayName)")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                    #else
                    Button {
                        appEnvironment?.navigationCoordinator.navigate(
                            to: .instanceBrowse(instance, initialTab: contentType.toBrowseTab())
                        )
                    } label: {
                        HStack(spacing: 4) {
                            Text(verbatim: "\(contentType.localizedTitle) - \(instance.displayName)")
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    #endif
                }
                .padding(.horizontal, listStyle == .inset ? 32 : 16)
                .padding(.top, 16)
                #if os(tvOS)
                .padding(.bottom, 24)
                #else
                .padding(.bottom, 8)
                #endif
                .frame(maxWidth: .infinity, alignment: .leading)

                if sectionLayout == .grid {
                    HomeHorizontalCards(
                        videos: limitedVideos,
                        queueSource: instanceQueueSource(instanceID: instanceID, contentType: contentType),
                        sourceLabel: contentType.localizedTitle,
                        loadMoreVideos: loadMoreInstanceContentCallback
                    )
                } else {
                    VideoListContent(listStyle: listStyle) {
                        ForEach(Array(limitedVideos.enumerated()), id: \.element.id) { index, video in
                            VideoListRow(
                                isLast: index == limitedVideos.count - 1,
                                rowStyle: .regular,
                                listStyle: listStyle
                            ) {
                                VideoRowView(video: video, style: .regular)
                                    .tappableVideo(
                                        video,
                                        queueSource: instanceQueueSource(instanceID: instanceID, contentType: contentType),
                                        sourceLabel: contentType.localizedTitle,
                                        videoList: limitedVideos,
                                        videoIndex: index,
                                        loadMoreVideos: loadMoreInstanceContentCallback
                                    )
                            }
                            #if !os(tvOS)
                            .videoSwipeActions(video: video)
                            #endif
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mediaSourceSection(sourceID: UUID) -> some View {
        if let source = appEnvironment?.mediaSourcesManager.sources.first(where: { $0.id == sourceID }),
           source.isEnabled {
            VStack(alignment: .leading, spacing: 0) {
                Text(source.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VideoListContent(listStyle: listStyle) {
                    VideoListRow(
                        isLast: true,
                        rowStyle: .regular,
                        listStyle: listStyle
                    ) {
                        Button {
                            appEnvironment?.navigationCoordinator.navigate(to: .mediaBrowser(source, path: "/"))
                        } label: {
                            HStack {
                                Image(systemName: source.type.systemImage)
                                    .foregroundStyle(.secondary)
                                Text("mediaSources.browse \(source.name)")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        loadPlaylistsData()
        loadBookmarksData()
        loadContinueWatchingData()
        loadHistoryData()
        loadChannelsData()
        loadRemoteDevicesData()
        cleanupOrphanedHomeInstanceItems()
        cleanupOrphanedHomeMediaSourceItems()
    }

    private func cleanupOrphanedHomeInstanceItems() {
        guard let instancesManager = appEnvironment?.instancesManager,
              let settingsManager = appEnvironment?.settingsManager else { return }

        let validIDs = Set(instancesManager.instances.map(\.id))
        settingsManager.cleanupOrphanedHomeInstanceItems(validInstanceIDs: validIDs)
    }

    private func cleanupOrphanedHomeMediaSourceItems() {
        guard let mediaSourcesManager = appEnvironment?.mediaSourcesManager,
              let settingsManager = appEnvironment?.settingsManager else { return }

        let validIDs = Set(mediaSourcesManager.sources.map(\.id))
        settingsManager.cleanupOrphanedHomeMediaSourceItems(validSourceIDs: validIDs)
    }

    private func loadPlaylistsData() {
        playlists = dataManager?.playlists() ?? []
    }

    private func loadBookmarksData() {
        bookmarksCount = dataManager?.bookmarksCount() ?? 0
        recentBookmarks = dataManager?.bookmarks(limit: 50) ?? []
    }

    private func loadContinueWatchingData() {
        let allHistory = dataManager?.watchHistory(limit: 100) ?? []
        // Filter to in-progress only (same logic as ContinueWatchingView)
        recentContinueWatching = allHistory.filter { !$0.isFinished && $0.watchedSeconds > 10 }
        continueWatchingCount = recentContinueWatching.count
    }

    private func loadHistoryData() {
        historyCount = dataManager?.watchHistoryCount() ?? 0
        recentHistory = dataManager?.watchHistory(limit: 50) ?? []
    }

    private func loadChannelsData() {
        channelsCount = dataManager?.subscriptions().count ?? 0
    }

    private func loadRemoteDevicesData() {
        discoveredDevicesCount = appEnvironment?.remoteControlCoordinator.discoveredDevices.count ?? 0
    }

    /// Refreshes Home instance content sections from network if cache is stale.
    /// Only refreshes enabled instance content sections (Popular/Trending/Feed).
    private func refreshHomeInstanceContent() async {
        guard let appEnvironment else { return }

        // Get all visible instance content sections from settings
        let visibleSections = settingsManager?.visibleSections() ?? []

        for section in visibleSections {
            if case .instanceContent(let instanceID, let contentType) = section {
                // Refresh if cache is stale
                if !appEnvironment.homeInstanceCache.isCacheValid(for: instanceID, contentType: contentType) {
                    await appEnvironment.homeInstanceCache.refresh(
                        instanceID: instanceID,
                        contentType: contentType,
                        using: appEnvironment
                    )
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HomeView()
    }
    .appEnvironment(.preview)
}
