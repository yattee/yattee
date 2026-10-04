//
//  HomeView.swift
//  Yattee
//
//  Home tab with shortcuts dashboard for Playlists, History, and Downloads.
//

import SwiftUI

struct HomeView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.presentAppSheet) private var presentAppSheet
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.scenePhase) private var scenePhase
    #if !os(tvOS) && !os(macOS)
    @Namespace private var sheetTransition
    #endif
    /// The device's own playlists. In an account context the card reads the
    /// remote playlists cache instead — the same store the playlists screen
    /// this shortcut leads to shows.
    @State private var playlists: [LocalPlaylist] = []
    @State private var bookmarksCount: Int = 0
    @State private var recentBookmarks: [Bookmark] = []
    @State private var continueWatchingCount: Int = 0
    @State private var recentContinueWatching: [WatchEntry] = []
    @State private var historyCount: Int = 0
    @State private var recentHistory: [WatchEntry] = []
    /// The account's server-side history, when that is what the history screen
    /// would show. `nil` in local mode — and while the account's first fetch is
    /// still out, which is what keeps the local numbers off an account's card.
    @State private var serverHistory: ServerHistorySnapshot?
    /// Which server-history load the state belongs to. Cancelling is not
    /// enough on its own: a page that already came back races the switch, and
    /// its rows would land on a context nobody is looking at any more.
    @State private var serverHistoryGeneration = 0
    #if !os(tvOS) && !os(macOS)
    @State private var showingSettings = false
    #endif
    @State private var showingRemoteControl = false
    @State private var showingCustomizeHome = false
    @State private var channelsCount: Int = 0
    @State private var discoveredDevicesCount: Int = 0
    @State private var feedCache = SubscriptionFeedCache.shared
    #if os(tvOS)
    /// Whether the first pass over the Home data has finished. Every section
    /// reads empty before it does, so the empty state waits for this rather than
    /// flashing over content that is on its way.
    @State private var hasLoadedHomeData = false
    #endif

    /// What one probe of the account's server history brought back.
    private struct ServerHistorySnapshot {
        /// How many entries the probe saw, or `nil` when the fetch failed.
        var count: Int?
        /// The probe came back full, so the history goes on past what it saw
        /// and `count` is a floor, not a total — the server has no count call.
        var countIsLowerBound = false
        /// The leading entries, hydrated for the section's rows.
        var videos: [Video] = []
    }

    /// How many IDs the server-history probe asks for in its single page.
    ///
    /// Large enough that most histories fit and the card shows a real total;
    /// a history that fills it shows this number as a floor instead. IDs only
    /// — nothing is hydrated past the section's few rows — so the size costs
    /// the server one array slice.
    private static let serverHistoryProbeSize = 500

    private var dataManager: DataManager? { appEnvironment?.dataManager }
    private var settingsManager: SettingsManager? { appEnvironment?.settingsManager }

    // MARK: - Context

    /// The account whose data Home is showing, or `nil` when it is the device's.
    ///
    /// The *effective* context, so a selected account that cannot be used right
    /// now shows the local numbers — the same fallback the screens the
    /// shortcuts lead to make.
    private var contextAccount: Account? {
        guard let appEnvironment,
              case let .account(id) = appEnvironment.dataContextValidator.effectiveContext
        else { return nil }

        return appEnvironment.accountsManager.account(id: id)
    }

    /// Whose history the card and the section read — resolved by the same rule
    /// as the history screen, so the shortcut can never promise a history the
    /// screen behind it will not show.
    private var historyDisplayMode: HistoryDisplayMode {
        guard let appEnvironment else { return .local }
        let account = contextAccount

        return HistoryDisplayMode.resolve(
            effectiveContext: appEnvironment.dataContextValidator.effectiveContext,
            account: account,
            capabilities: account.flatMap { appEnvironment.accountsManager.capabilities(for: $0) }
        )
    }

    /// The account's playlists as last fetched, or `nil` in local mode — read
    /// live from the same cache the playlists screen shows, so a create or a
    /// delete there moves this count without a reload.
    private var remotePlaylists: [Playlist]? {
        guard let appEnvironment, let account = contextAccount else { return nil }
        return appEnvironment.remotePlaylistsCache.playlists(for: account.id)
    }

    private var accentColor: Color {
        appEnvironment?.settingsManager.resolvedAccentColor ?? .accentColor
    }

    #if !os(tvOS)
    private var downloadManager: DownloadManager? { appEnvironment?.downloadManager }
    #endif

    private var columns: [GridItem] {
        #if os(tvOS)
        [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 16)]
        #else
        [GridItem(.adaptive(minimum: 150), spacing: 8)]
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
        // Split from `chrome` so the modifier chain stays within what the
        // type-checker will resolve in one expression.
        dataObservers(chrome)
    }

    private var chrome: some View {
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
            // No switcher wherever a sidebar shows one: the macOS sidebar row
            // and the iPad sidebar's bottom bar are the persistent switcher
            // surfaces there, so the toolbar menu is compact-width-only.
            #if !os(tvOS) && !os(macOS)
            if DataContextSwitcherVisibility.showsToolbarPickers(in: appEnvironment, horizontalSizeClass: horizontalSizeClass) {
                ToolbarItem(placement: .primaryAction) {
                    DataContextSwitcherMenu()
                }
            }
            #endif
            #if !os(tvOS) && !os(macOS)
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
        #if !os(tvOS) && !os(macOS)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .liquidGlassSheetContent(sourceID: "homeSettings", in: sheetTransition)
        }
        .onChange(of: appEnvironment?.navigationCoordinator.dismissSettingsTrigger) {
            showingSettings = false
        }
        #endif
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
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 450)
            #endif
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
            #if os(tvOS)
            // The disk caches are the last of the on-device data to land, so the
            // empty state is honest from here on. A network refresh below can
            // still add content later; it must not hold an empty Home behind a
            // spinner for as long as a request can take.
            hasLoadedHomeData = true
            #endif
            await refreshHomeInstanceContent()
        }
        .onChange(of: appEnvironment?.navigationCoordinator.isPlayerExpanded) { _, isExpanded in
            // Refresh when player is collapsed
            if isExpanded == false {
                loadData()
            }
        }
        .onChange(of: appEnvironment?.navigationCoordinator.router.selection) { _, newSelection in
            if newSelection == .home {
                loadData()
            }
        }
        .onChange(of: showingCustomizeHome) { _, isShowing in
            if !isShowing {
                loadData()
            }
        }
    }

    /// The notification subscriptions, hung on the content as one group.
    private func dataObservers(_ content: some View) -> some View {
        content
        .onReceive(NotificationCenter.default.publisher(for: .bookmarksDidChange)) { _ in
            loadBookmarksData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
            // The device's own history changed; an account's server history is
            // told about below, and a local write is not news about it.
            loadLocalHistoryData()
            loadContinueWatchingData()
        }
        // A watch was posted to the account's server history — the count and
        // the section's front rows just moved.
        .onReceive(NotificationCenter.default.publisher(for: .serverWatchHistoryDidUpdate)) { _ in
            if case .server = historyDisplayMode {
                loadServerHistoryIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .playlistsDidChange)) { _ in
            loadPlaylistsData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .subscriptionsDidChange)) { _ in
            loadChannelsData()
        }
        // Selecting another account — or local — changes whose channels count
        // and feed this is. AppEnvironment already swapped or cleared the
        // account-scoped caches; this re-reads the counts and, when the feed
        // section is on Home, refills the feed the clearing just emptied.
        .onReceive(NotificationCenter.default.publisher(for: .dataContextDidChange)) { _ in
            loadData()
            refreshFeedIfNeeded()
        }
        // The same, without the context moving: the credential behind the
        // account was replaced, so the counts may now be someone else's.
        .onReceive(NotificationCenter.default.publisher(for: .accountCredentialDidChange)) { _ in
            loadData()
            refreshFeedIfNeeded()
        }
        // A status, an account or an instance changing moves reads between the
        // account and local without the stored context moving at all.
        .onReceive(NotificationCenter.default.publisher(for: .accountStatusesDidChange)) { _ in
            loadData()
            refreshFeedIfNeeded()
        }
    }

    // MARK: - Main Content

    #if os(tvOS)
    /// True on tvOS when no Home section would render content — prevents a focus trap
    /// where the detail pane would otherwise be completely empty.
    ///
    /// Each case mirrors what `sectionView(for:)` actually renders: a section with
    /// nothing to show renders nothing, so it must not count as content here.
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
                if case .server = historyDisplayMode {
                    if !(serverHistory?.videos.isEmpty ?? true) { return false }
                } else if !recentHistory.isEmpty {
                    return false
                }
            case .downloads:
                break
            case .remoteServers:
                if !homeRemoteServers.isEmpty { return false }
            case .fileSources:
                if !homeFileSources.isEmpty { return false }
            case .instanceContent(let instanceID, let contentType):
                if hasInstanceContent(instanceID: instanceID, contentType: contentType) { return false }
            case .mediaSource:
                // Legacy, stripped on load and rendered as empty.
                break
            }
        }
        return true
    }

    /// Whether an instance content section has something to render, matching the
    /// conditions in `instanceContentSection(instanceID:contentType:)`.
    private func hasInstanceContent(instanceID: UUID, contentType: InstanceContentType) -> Bool {
        guard let instance = appEnvironment?.instancesManager.instances.first(where: { $0.id == instanceID }),
              instance.isEnabled,
              let videos = appEnvironment?.homeInstanceCache.videos(for: instanceID, contentType: contentType) else {
            return false
        }
        return !videos.isEmpty
    }

    /// Whether any source is configured, read from the same managers the Sources
    /// screen builds its list from. An empty Home is not the same thing as a
    /// fresh install: with sources already added, telling the user to add one is
    /// simply wrong.
    private var hasConfiguredSources: Bool {
        let hasInstances = !(appEnvironment?.instancesManager.instances.isEmpty ?? true)
        let hasMediaSources = !(appEnvironment?.mediaSourcesManager.sources.isEmpty ?? true)
        return hasInstances || hasMediaSources
    }

    private var emptyHomeView: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                if hasConfiguredSources {
                    // Sources are set up, Home simply has nothing to show yet.
                    Text(String(localized: "common.noContent"))
                        .font(.title2)
                        .fontWeight(.semibold)
                } else {
                    Text(String(localized: "home.tvos.empty.title"))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(String(localized: "home.tvos.empty.message"))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Button {
                appEnvironment?.navigationCoordinator.router.select(.sources)
            } label: {
                Label(String(localized: "home.tvos.empty.openSources"), systemImage: "externaldrive.connected.to.line.below")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingHomeView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif

    @ViewBuilder
    private var mainContent: some View {
        #if os(tvOS)
        if isHomeEmpty {
            if hasLoadedHomeData {
                emptyHomeView
            } else {
                loadingHomeView
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    homeContent
                }
            }
            .scrollClipDisabled()
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
            #else
            Button(action: action) {
                HStack(spacing: 4) {
                    Text(title)
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .foregroundStyle(accentColor)
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
        #if os(macOS)
        HStack {
            Spacer()
            Button {
                showingCustomizeHome = true
            } label: {
                Label(String(localized: "home.customize"), systemImage: "gear")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            Spacer()
        }
        .padding(.top, 16)
        .padding(.bottom, 32)
        #else
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
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.top, 16)
        .padding(.bottom, 32)
        #endif
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
        let gridSpacing: CGFloat = 16
        #else
        let gridSpacing: CGFloat = 8
        #endif

        let shortcuts = settingsManager?.visibleShortcuts() ?? HomeShortcutItem.defaultOrder

        return LazyVGrid(columns: columns, spacing: gridSpacing) {
            ForEach(Array(shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                shortcutCardView(for: shortcut)
                    .environment(\.homeShortcutColorfulColor, colorfulColor(atPosition: index))
                    #if !os(tvOS)
                    .contextMenu {
                        hideShortcutButton(for: shortcut)
                        editShortcutsButton
                    }
                    #endif
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

    /// Resolves the Regular-style fill color for a shortcut at the given grid
    /// position from the selected palette (custom colors and accent color when
    /// applicable).
    private func colorfulColor(atPosition position: Int) -> Color {
        let palette = settingsManager?.homeShortcutColorfulPalette ?? .accent
        let customHex = settingsManager?.homeShortcutCustomPaletteColors ?? []
        let accentColor = settingsManager?.resolvedAccentColor ?? .accentColor
        return HomeShortcutColorfulPalette.color(forPosition: position, palette: palette, customHex: customHex, accentColor: accentColor)
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
            #if !os(tvOS)
            .contextMenu {
                hideShortcutButton(for: shortcut)
                editShortcutsButton
            }
            #endif
        }
    }

    #if !os(tvOS)
    /// Context menu action that hides the given shortcut from Home.
    private func hideShortcutButton(for shortcut: HomeShortcutItem) -> some View {
        Button {
            guard let settingsManager else { return }
            var visibility = settingsManager.homeShortcutVisibility
            visibility[shortcut] = false
            settingsManager.homeShortcutVisibility = visibility
        } label: {
            Label(String(localized: "home.hideShortcut"), systemImage: "eye.slash")
        }
    }

    /// Context menu action that opens the Home settings sheet to reorder/toggle shortcuts.
    private var editShortcutsButton: some View {
        Button {
            showingCustomizeHome = true
        } label: {
            Label(String(localized: "home.editShortcuts"), systemImage: "gear")
        }
    }
    #endif

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
            presentAppSheet(.openLink(nil))
        } label: {
            HomeShortcutCardView(
                icon: "link",
                title: String(localized: "home.shortcut.openURL"),
                count: 0,
                subtitle: "",
                showsCount: false,
                colorfulColor: HomeShortcutItem.openURL.cardColor
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
                showsCount: false,
                colorfulColor: HomeShortcutItem.remoteControl.cardColor,
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
                count: playlistsCardCount,
                subtitle: playlistsCardSubtitle,
                colorfulColor: HomeShortcutItem.playlists.cardColor
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
                subtitle: formatCount(bookmarksCount, singular: "home.count.bookmark", plural: "home.count.bookmarks"),
                colorfulColor: HomeShortcutItem.bookmarks.cardColor
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
                subtitle: formatCount(continueWatchingCount, singular: "home.count.video", plural: "home.count.videos"),
                colorfulColor: HomeShortcutItem.continueWatching.cardColor
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
                count: historyCardCount,
                subtitle: historyCardSubtitle,
                colorfulColor: HomeShortcutItem.history.cardColor
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
                subtitle: formatCount(count, singular: "home.count.video", plural: "home.count.videos"),
                colorfulColor: HomeShortcutItem.downloads.cardColor
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
                subtitle: formatCount(channelsCount, singular: "home.count.channel", plural: "home.count.channels"),
                colorfulColor: HomeShortcutItem.channels.cardColor
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
                subtitle: String(localized: "home.subscriptions.subtitle"),
                showsCount: false,
                colorfulColor: HomeShortcutItem.subscriptions.cardColor
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
        let instancesCount = appEnvironment?.instancesManager.enabledInstances.count ?? 0
        let count = mediaSourcesCount + instancesCount
        return Button {
            appEnvironment?.navigationCoordinator.navigate(to: .mediaSources)
        } label: {
            HomeShortcutCardView(
                icon: "externaldrive.connected.to.line.below",
                title: "Sources",
                count: count,
                subtitle: count == 1 ? "1 source" : "\(count) sources",
                colorfulColor: HomeShortcutItem.mediaSources.cardColor
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
                    subtitle: instance.displayName,
                    showsCount: false,
                    colorfulColor: HomeShortcutItem.instanceContent(instanceID: instanceID, contentType: contentType).cardColor
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
                    subtitle: source.type.displayName,
                    showsCount: false,
                    colorfulColor: HomeShortcutItem.mediaSource(sourceID: sourceID).cardColor
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
            presentAppSheet(.openLink(nil))
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
                subtitle: playlistsCardSubtitle
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
                subtitle: historyCardSubtitle
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
        let instancesCount = appEnvironment?.instancesManager.enabledInstances.count ?? 0
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
    ///
    /// `lowerBound` marks a count the source could only see the start of — a
    /// server history longer than one probe — and reads "500+ videos".
    private func formatCount(_ count: Int, singular: String.LocalizationValue, plural: String.LocalizationValue, lowerBound: Bool = false) -> String {
        let formattedCount = CountFormatter.compact(count) + (lowerBound ? "+" : "")
        let key = count == 1 ? singular : plural
        return String(localized: "\(formattedCount) \(String(localized: key))")
    }

    // MARK: - Context-Scoped Card Values

    /// What the playlists card counts: the account's server-side list when one
    /// is selected, the device's own otherwise.
    private var playlistsCardCount: Int {
        guard contextAccount != nil else { return playlists.count }
        return remotePlaylists?.count ?? 0
    }

    /// An account list that has not come back yet says so rather than showing
    /// a zero that is really "not asked yet".
    private var playlistsCardSubtitle: String {
        if contextAccount != nil, remotePlaylists == nil { return "—" }
        return formatCount(playlistsCardCount, singular: "home.count.playlist", plural: "home.count.playlists")
    }

    private var historyCardCount: Int {
        guard case .server = historyDisplayMode else { return historyCount }
        return serverHistory?.count ?? 0
    }

    private var historyCardSubtitle: String {
        guard case .server = historyDisplayMode else {
            return formatCount(historyCount, singular: "home.count.video", plural: "home.count.videos")
        }
        // Still fetching, or the fetch failed — either way the local number
        // is not this account's, so the card holds its tongue instead.
        guard let count = serverHistory?.count else { return "—" }
        return formatCount(
            count,
            singular: "home.count.video",
            plural: "home.count.videos",
            lowerBound: serverHistory?.countIsLowerBound == true
        )
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
            if case .server = historyDisplayMode {
                if let videos = serverHistory?.videos, !videos.isEmpty {
                    serverHistorySection(videos: videos)
                }
            } else if !recentHistory.isEmpty {
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
        case .remoteServers:
            if !homeRemoteServers.isEmpty {
                remoteServersSection
            }
        case .fileSources:
            if !homeFileSources.isEmpty {
                fileSourcesSection
            }
        case .instanceContent(let instanceID, let contentType):
            instanceContentSection(instanceID: instanceID, contentType: contentType)
        case .mediaSource:
            // Media sources are shortcuts-only; any legacy media-source section is
            // stripped by removeAllHomeMediaSourceSections() on load, so this is
            // unreachable in practice. Rendered as empty for defense-in-depth.
            EmptyView()
        }
    }

    // MARK: - Sources Sections

    /// Enabled remote servers in the Sources screen's order.
    private var homeRemoteServers: [Instance] {
        let instances = appEnvironment?.instancesManager.enabledInstances ?? []
        return appEnvironment?.sourcesSettings.sorted(instances) ?? instances
    }

    /// Enabled file sources in the Sources screen's order.
    private var homeFileSources: [MediaSource] {
        let sources = appEnvironment?.mediaSourcesManager.enabledSources ?? []
        return appEnvironment?.sourcesSettings.sorted(sources) ?? sources
    }

    private var remoteServersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "sources.section.remoteServers") {
                appEnvironment?.navigationCoordinator.navigate(to: .mediaSources)
            }

            VideoListContent(listStyle: listStyle) {
                let instances = homeRemoteServers
                ForEach(Array(instances.enumerated()), id: \.element.id) { index, instance in
                    SourceListRow(isLast: index == instances.count - 1, listStyle: listStyle) {
                        Button {
                            appEnvironment?.navigationCoordinator.navigate(to: .instanceBrowse(instance))
                        } label: {
                            homeSourceRow(
                                systemImage: instance.type.systemImage,
                                name: instance.displayName,
                                detail: "\(instance.type.displayName) - \(instance.url.host ?? instance.url.absoluteString)"
                            )
                        }
                        #if os(macOS)
                        .buttonStyle(.plain)
                        #elseif os(tvOS)
                        .buttonStyle(TVHomeRowButtonStyle())
                        #else
                        .foregroundStyle(.primary)
                        #endif
                    }
                }
            }
        }
    }

    private var fileSourcesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "sources.section.fileSources") {
                appEnvironment?.navigationCoordinator.navigate(to: .mediaSources)
            }

            VideoListContent(listStyle: listStyle) {
                let sources = homeFileSources
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                    let needsPassword = appEnvironment?.mediaSourcesManager.needsPassword(for: source) ?? false
                    SourceListRow(isLast: index == sources.count - 1, listStyle: listStyle) {
                        Button {
                            if needsPassword {
                                // The browser can't open without credentials; the
                                // Sources screen holds the edit flow that fixes it.
                                appEnvironment?.navigationCoordinator.navigate(to: .mediaSources)
                            } else {
                                appEnvironment?.navigationCoordinator.navigate(to: .mediaBrowser(source, path: "/"))
                            }
                        } label: {
                            homeSourceRow(
                                systemImage: source.type.systemImage,
                                name: source.name,
                                detail: "\(source.type.displayName) - \(source.urlDisplayString)",
                                needsPassword: needsPassword
                            )
                        }
                        #if os(macOS)
                        .buttonStyle(.plain)
                        #elseif os(tvOS)
                        .buttonStyle(TVHomeRowButtonStyle())
                        #else
                        .foregroundStyle(.primary)
                        #endif
                    }
                }
            }
        }
    }

    /// Row content matching the Sources screen's listing.
    private func homeSourceRow(systemImage: String, name: String, detail: String, needsPassword: Bool = false) -> some View {
        #if os(tvOS)
        let rowSpacing: CGFloat = 24
        #else
        let rowSpacing: CGFloat = 12
        #endif
        #if os(macOS)
        let iconFont: Font = .title3
        let iconFrameWidth: CGFloat = 24
        let titleFont: Font = .body
        #else
        let iconFont: Font = .title2
        let iconFrameWidth: CGFloat = 32
        let titleFont: Font = .headline
        #endif
        return HStack(spacing: rowSpacing) {
            Image(systemName: systemImage)
                .font(iconFont)
                .foregroundStyle(.tint)
                .frame(width: iconFrameWidth)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(titleFont)
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if needsPassword {
                    Label(String(localized: "sources.status.authRequired"), systemImage: "key.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            #if !os(macOS)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
            #endif
        }
        .contentShape(Rectangle())
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

    /// The account's recent server-side history, already hydrated and limited.
    ///
    /// Plain video rows, no swipe delete: a server delete belongs to the full
    /// history screen, which owns the confirmation and the error for it.
    private func serverHistorySection(videos: [Video]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "home.recentHistory.title") {
                appEnvironment?.navigationCoordinator.navigate(to: .history)
            }

            if sectionLayout == .grid {
                HomeHorizontalCards(
                    videos: videos,
                    queueSource: recentHistoryQueueSource,
                    sourceLabel: String(localized: "queue.source.history"),
                    loadMoreVideos: loadMoreRecentHistoryCallback
                )
            } else {
                VideoListContent(listStyle: listStyle) {
                    ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                        VideoListRow(
                            isLast: index == videos.count - 1,
                            rowStyle: .regular,
                            listStyle: listStyle
                        ) {
                            VideoRowView(video: video, style: .regular)
                                .tappableVideo(
                                    video,
                                    queueSource: recentHistoryQueueSource,
                                    sourceLabel: String(localized: "queue.source.history"),
                                    videoList: videos,
                                    videoIndex: index,
                                    loadMoreVideos: loadMoreRecentHistoryCallback
                                )
                        }
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
                        .foregroundStyle(accentColor)
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
                        .foregroundStyle(accentColor)
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
        // Media sources are shortcuts-only; drop any legacy media-source sections.
        appEnvironment?.settingsManager.removeAllHomeMediaSourceSections()
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
        refreshRemotePlaylistsIfNeeded()
    }

    /// Asks for the account's playlist list the first time this context needs
    /// it. Reads come off the cache live, so the count appears when the fetch
    /// lands and follows every mutation after — this only has to make sure the
    /// first fetch happens even when the playlists screen was never opened.
    private func refreshRemotePlaylistsIfNeeded() {
        guard let appEnvironment, let account = contextAccount,
              appEnvironment.remotePlaylistsCache.playlists(for: account.id) == nil
        else { return }

        Task {
            // The cache fences by account generation and orders results
            // itself; a failure simply leaves the count reading "—", and the
            // playlists screen owns showing the error.
            try? await appEnvironment.remotePlaylistsCache.refreshList(for: account)
        }
    }

    private func loadBookmarksData() {
        bookmarksCount = dataManager?.bookmarksCount() ?? 0
        recentBookmarks = dataManager?.bookmarks(limit: 50) ?? []
    }

    private func loadContinueWatchingData() {
        let allHistory = dataManager?.watchHistory(limit: 100) ?? []
        // Filter to in-progress only (same logic as ContinueWatchingView)
        recentContinueWatching = allHistory.filter { !$0.isFinished && !$0.isLive && $0.watchedSeconds > 10 }
        continueWatchingCount = recentContinueWatching.count
    }

    private func loadHistoryData() {
        loadLocalHistoryData()
        loadServerHistoryIfNeeded()
    }

    /// The device's own history alone — what a local write changes. The
    /// account's is the server's to change, and announced separately.
    private func loadLocalHistoryData() {
        historyCount = dataManager?.watchHistoryCount() ?? 0
        recentHistory = dataManager?.watchHistory(limit: 50) ?? []
    }

    /// One probe of the account's server history: the count for the card, the
    /// leading rows for the section.
    private func loadServerHistoryIfNeeded() {
        serverHistoryGeneration += 1
        let generation = serverHistoryGeneration

        guard case let .server(account) = historyDisplayMode, let appEnvironment else {
            serverHistory = nil
            return
        }

        let limit = sectionItemsLimit

        Task {
            do {
                let ids = try await appEnvironment.accountService.watchHistory(
                    page: 1,
                    maxResults: Self.serverHistoryProbeSize,
                    for: account
                )
                guard generation == serverHistoryGeneration else { return }

                // The server re-bumps a re-watch rather than duplicating it,
                // but the rows key a ForEach — deduped rather than trusted.
                var seen = Set<String>()
                let uniqueIDs = ids.filter { seen.insert($0).inserted }

                let videos = await hydrateServerHistory(
                    ids: Array(uniqueIDs.prefix(limit)),
                    account: account,
                    using: appEnvironment
                )
                guard generation == serverHistoryGeneration else { return }

                serverHistory = ServerHistorySnapshot(
                    count: uniqueIDs.count,
                    countIsLowerBound: ids.count >= Self.serverHistoryProbeSize,
                    videos: videos
                )
            } catch {
                guard generation == serverHistoryGeneration else { return }
                // Failed is not local: the card shows "—" and no section,
                // never the device's numbers under an account's name.
                serverHistory = ServerHistorySnapshot(count: nil)
            }
        }
    }

    /// Rows for the leading server-history IDs, from local data where there is
    /// some — a video watched on this device is already known in full — and a
    /// metadata fetch for the rest. Bounded by the section limit, so this is a
    /// handful of requests at most.
    ///
    /// A fetch that fails leaves the row as its ID placeholder rather than
    /// dropping it: the account watched it, and a history missing rows it
    /// cannot describe is a wrong history.
    private func hydrateServerHistory(
        ids: [String],
        account: Account,
        using appEnvironment: AppEnvironment
    ) async -> [Video] {
        guard let instance = appEnvironment.accountsManager.instance(for: account) else {
            return ids.map { Video.metadataPlaceholder(for: $0) }
        }

        let known: [String: Video] = Dictionary(
            uniqueKeysWithValues: ids.compactMap { id in
                dataManager?.watchEntry(for: id).map { (id, $0.toVideo()) }
            }
        )

        return await withTaskGroup(of: (Int, Video).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask { @MainActor in
                    if let video = known[id] { return (index, video) }
                    let fetched = try? await appEnvironment.contentService.video(id: id, instance: instance)
                    return (index, fetched ?? .metadataPlaceholder(for: id))
                }
            }

            var videos = [Video?](repeating: nil, count: ids.count)
            for await (index, video) in group {
                videos[index] = video
            }
            return videos.compactMap { $0 }
        }
    }

    private func loadChannelsData() {
        guard let service = appEnvironment?.subscriptionService else {
            channelsCount = 0
            return
        }

        // Local accounts always have a count; server accounts only after their
        // in-memory cache is populated — fetch it once in the background otherwise.
        if let cached = service.cachedSubscriptionCount {
            channelsCount = cached
        } else {
            // Captured so a fetch that outlives an account switch cannot land
            // its count on whichever context is selected by the time it returns.
            let requestContext = appEnvironment?.dataContextValidator.effectiveContext
            Task {
                if let channels = try? await service.fetchSubscriptions(),
                   requestContext == appEnvironment?.dataContextValidator.effectiveContext {
                    channelsCount = channels.count
                }
            }
        }
    }

    /// Refills the feed section after an account switch emptied its cache.
    ///
    /// Only when Home actually shows the feed: without the section on screen
    /// there is nothing to refill, and the Subscriptions tab refreshes for
    /// itself when opened. The validity/loading gate is the same one
    /// SubscriptionsView uses, so a switch that kept the cache (a status flap
    /// fencing rather than clearing) does not refetch what is already there.
    private func refreshFeedIfNeeded() {
        guard let appEnvironment else { return }

        let sections = settingsManager?.visibleSections() ?? []
        guard sections.contains(.feed) else { return }
        guard !feedCache.isCacheValid(using: settingsManager), !feedCache.isLoading else { return }

        Task {
            await feedCache.refresh(using: appEnvironment)
        }
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
