//
//  SubscriptionsView.swift
//  Yattee
//
//  Subscriptions tab with channel filter strip and feed.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SubscriptionsView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var sheetTransition
    #if os(tvOS)
    @FocusState private var focusedVideoID: String?
    #endif
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var feedCache = SubscriptionFeedCache.shared
    @State private var subscriptions: [Subscription] = []
    @State private var subscriptionsLoaded = false
    /// The effective context the visible subscriptions were loaded for, so a
    /// status change that does not move it does not force a reload.
    @State private var loadedContext: DataContext?
    /// How many times the feed has been tried again since it last stopped on a
    /// failure that can lift, so each attempt restarts the wait for the next one.
    @State private var feedRetryAttempt = 0
    @State private var selectedChannelID: String? = nil
    @State private var errorMessage: String?
    @State private var watchEntriesMap: [String: WatchEntry] = [:]
    @State private var showViewOptions = false
    #if os(macOS)
    @State private var showSubscriptionsData = false
    @State private var pendingSubscriptionsData = false
    #endif

    // View options (persisted)
    @AppStorage("subscriptionsLayout") private var layout: VideoListLayout = .list
    @AppStorage("subscriptionsRowStyle") private var rowStyle: VideoRowStyle = .regular
    @AppStorage("subscriptionsGridColumns") private var gridColumns = 2
    @AppStorage("subscriptionsHideWatched") private var hideWatched = false
    @AppStorage("subscriptionsChannelStripSize") private var channelStripSize: ChannelStripSize = .normal
    @AppStorage("subscriptionsShowSidebar") private var showSidebar = true
    /// Whether the last completed load produced enough channels for the sidebar,
    /// so its space can be reserved before the next load finishes.
    @AppStorage("subscriptionsSidebarExpected") private var sidebarExpected = false
    #if os(macOS)
    @AppStorage("subscriptionsMacOSSidebarWidth") private var macOSSidebarWidth = 240.0
    @State private var macOSSidebarDragStartWidth: Double?
    #elseif os(iOS)
    @AppStorage("subscriptionsIPadSidebarWidth") private var iPadSidebarWidth = 260.0
    @State private var iPadSidebarDragStartWidth: Double?
    #endif

    /// List style from centralized settings.
    private var listStyle: VideoListStyle {
        appEnvironment?.settingsManager.listStyle ?? .inset
    }

    // Grid layout configuration
    @State private var viewWidth: CGFloat = 0
    private var gridConfig: GridLayoutConfiguration {
        GridLayoutConfiguration(viewWidth: viewWidth, gridColumns: gridColumns)
    }

    private var viewOptionsForm: some View {
        Form {
            Section {
                #if os(macOS)
                Toggle("viewOptions.showSidebar", isOn: $showSidebar)
                #elseif os(iOS)
                if isIPadRegular {
                    Toggle("viewOptions.showSidebar", isOn: $showSidebar)
                }
                #elseif os(tvOS)
                PlatformMenuPicker(String(localized: "viewOptions.showSidebar"), selection: $showSidebar) {
                    Text("common.on").tag(true)
                    Text("common.off").tag(false)
                }
                #endif

                // Layout picker (inline menu)
                PlatformMenuPicker(String(localized: "viewOptions.layout"), selection: $layout) {
                    ForEach(VideoListLayout.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }

                // List-specific options
                if layout == .list {
                    PlatformMenuPicker(String(localized: "viewOptions.rowSize"), selection: $rowStyle) {
                        Text("viewOptions.rowSize.compact").tag(VideoRowStyle.compact)
                        Text("viewOptions.rowSize.regular").tag(VideoRowStyle.regular)
                        Text("viewOptions.rowSize.large").tag(VideoRowStyle.large)
                    }
                }

                // Grid-specific options
                if layout == .grid {
                    #if os(tvOS)
                    Picker("viewOptions.columns.header", selection: $gridColumns) {
                        ForEach(GridConstants.minAllowedColumns...max(GridConstants.minAllowedColumns, gridConfig.maxColumns), id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                    #else
                    Stepper(
                        "viewOptions.columns \(min(max(GridConstants.minAllowedColumns, gridColumns), gridConfig.maxColumns))",
                        value: $gridColumns,
                        in: GridConstants.minAllowedColumns...max(GridConstants.minAllowedColumns, gridConfig.maxColumns)
                    )
                    #endif
                }

                #if os(tvOS)
                PlatformMenuPicker(String(localized: "viewOptions.hideWatched"), selection: $hideWatched) {
                    Text("common.on").tag(true)
                    Text("common.off").tag(false)
                }
                #else
                Toggle("viewOptions.hideWatched", isOn: $hideWatched)
                #endif

                #if os(iOS)
                Picker("viewOptions.channelStrip", selection: $channelStripSize) {
                    ForEach(ChannelStripSize.allCases, id: \.self) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .disabled(isIPadRegular && showSidebar)
                #endif
            }

            #if os(macOS)
            Section {
                Button {
                    pendingSubscriptionsData = true
                    showViewOptions = false
                } label: {
                    Label(String(localized: "manageChannels.subscriptionsData"), systemImage: "person.2.badge.gearshape")
                }
            }
            #elseif os(iOS)
            Section {
                NavigationLink {
                    SubscriptionsSettingsView()
                } label: {
                    Label(String(localized: "manageChannels.subscriptionsData"), systemImage: "person.2.badge.gearshape")
                }
            }
            #endif
        }
    }

    #if os(macOS)
    private var subscriptionsDataSheet: some View {
        NavigationStack {
            SubscriptionsSettingsView()
                .toolbar {
                    sheetCloseToolbarItem { showSubscriptionsData = false }
                }
        }
        .frame(minWidth: 500, minHeight: 450)
    }
    #endif

    /// The feed error worth showing, if any — the banner takes over only for
    /// the errors it is already the answer to.
    private var displayedFeedError: FeedLoadState.FeedLoadError? {
        feedCache.feedLoadState.displayedError(contextBannerVisible: contextUnavailability != nil)
    }

    private var isShowingFullScreenError: Bool {
        displayedFeedError != nil && feedCache.videos.isEmpty
    }

    /// Whether the feed stopped on a failure the banner is already the answer
    /// to, and so has nothing of its own to show.
    ///
    /// Without this the view falls back through to the spinner it started on
    /// and stays there for as long as the account is unusable: the request that
    /// would replace it is the one that cannot be made.
    private var feedSettledOnAnsweredError: Bool {
        guard case .error = feedCache.feedLoadState else { return false }
        return displayedFeedError == nil
    }

    /// How long a feed that failed on the network waits before trying again.
    private static let feedRetryInterval: TimeInterval = 60

    /// The failure the feed is currently sitting on, if it is one that trying
    /// again could answer differently.
    ///
    /// A network error always is. So is the Yattee Server the local feed asks
    /// for while it is only standing in for an account whose server could not
    /// be reached — that request is not the real answer, and the one that is
    /// comes back on a status expiry nothing here is watching. An account that
    /// genuinely has no Yattee Server never arms this: the unavailability it
    /// gates on is `nil` for a context the user selected themselves.
    private var feedRetryToken: Int? {
        guard feedCache.feedLoadState.warrantsPeriodicRetry(unavailability: contextUnavailability)
        else { return nil }
        return feedRetryAttempt
    }

    private var dataManager: DataManager? { appEnvironment?.dataManager }
    private var subscriptionService: SubscriptionService? { appEnvironment?.subscriptionService }
    private var accentColor: Color { appEnvironment?.settingsManager.resolvedAccentColor ?? .accentColor }
    private var yatteeServer: Instance? {
        appEnvironment?.instancesManager.enabledYatteeServerInstances.first
    }
    private var yatteeServerURL: URL? { yatteeServer?.url }
    private var yatteeServerAuthHeader: String? {
        guard let server = yatteeServer else { return nil }
        return appEnvironment?.basicAuthCredentialsManager.basicAuthHeader(for: server)
    }

    /// Generates a unique ID based on instances configuration.
    private var instanceConfigurationID: String {
        guard let instances = appEnvironment?.instancesManager.instances else {
            return "none"
        }
        return instances
            .filter { $0.type == .yatteeServer }
            .map { "\($0.id):\($0.isEnabled)" }
            .joined(separator: "|")
    }

    /// Videos filtered by selected channel and watch status.
    private var filteredVideos: [Video] {
        var videos = feedCache.videos

        if let channelID = selectedChannelID {
            videos = videos.filter { $0.author.id == channelID }
        }

        if hideWatched {
            videos = videos.filter { video in
                guard let entry = watchEntriesMap[video.id.videoID] else { return true }
                return !entry.isFinished
            }
        }

        return videos
    }

    /// The currently selected subscription (if any).
    private var selectedSubscription: Subscription? {
        guard let channelID = selectedChannelID else { return nil }
        return subscriptions.first { $0.channelID == channelID }
    }

    /// Banner showing feed loading progress when server is fetching channels.
    @ViewBuilder
    private var feedStatusBanner: some View {
        switch feedCache.feedLoadState {
        case .partiallyLoaded(let ready, let pending, let errors):
            let total = ready + pending + errors
            HStack(spacing: 8) {
                if pending > 0 {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                if errors > 0 {
                    Text("subscriptions.loadingFeedWithErrors \(ready) \(total) \(errors)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text("subscriptions.loadingFeed \(ready) \(total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            #if os(tvOS)
            .background(Color.black.opacity(0.3))
            #endif

        case .error:
            if let error = displayedFeedError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(errorMessage(for: error))
                        .font(.caption)
                }
                .foregroundStyle(.red)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                #if os(tvOS)
                .background(Color.black.opacity(0.3))
                #endif
            }

        case .loadingMore:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text(String(localized: "subscriptions.loadingMore"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            #if os(tvOS)
            .background(Color.black.opacity(0.3))
            #endif

        default:
            EmptyView()
        }
    }

    /// Converts feed error to localized message.
    private func errorMessage(for error: FeedLoadState.FeedLoadError) -> String {
        switch error {
        case .yatteeServerRequired:
            return String(localized: "subscriptions.error.yatteeServerRequired")
        case .notAuthenticated:
            return String(localized: "subscriptions.error.notAuthenticated")
        case .networkError(let message):
            return message
        }
    }

    /// Subscriptions sorted by most recent video upload date.
    private var sortedSubscriptions: [Subscription] {
        var latestVideoDate: [String: Date] = [:]
        for video in feedCache.videos {
            let channelID = video.author.id
            let videoDate = video.publishedAt ?? .distantPast
            if let existing = latestVideoDate[channelID] {
                if videoDate > existing {
                    latestVideoDate[channelID] = videoDate
                }
            } else {
                latestVideoDate[channelID] = videoDate
            }
        }

        return subscriptions.sorted { sub1, sub2 in
            let date1 = latestVideoDate[sub1.channelID] ?? .distantPast
            let date2 = latestVideoDate[sub2.channelID] ?? .distantPast
            return date1 > date2
        }
    }

    /// Gets the watch progress (0.0-1.0) for a video, or nil if not watched/finished.
    private func watchProgress(for video: Video) -> Double? {
        guard let entry = watchEntriesMap[video.id.videoID] else { return nil }
        let progress = entry.progress
        return progress > 0 && progress < 1 ? progress : nil
    }

    /// Why the selected account is not the one answering, when it is not.
    ///
    /// Only for an account context: local data is never unavailable, and the
    /// fallback the banner explains is local data itself.
    private var contextUnavailability: DataContextUnavailability? {
        guard appEnvironment?.accountsManager.currentContext.isLocal == false else { return nil }
        return appEnvironment?.dataContextValidator.unavailability
    }

    /// View options button lives on the leading edge on macOS, trailing elsewhere.
    private var viewOptionsPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .navigation
        #else
        .primaryAction
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ZStack {
                    #if os(tvOS)
                    HStack(alignment: .top, spacing: 24) {
                        if showSidebar && subscriptionsLoaded && subscriptions.count > 1 {
                            tvOSChannelsSidebar
                                .frame(width: max(geometry.size.width * 0.28, 360), alignment: .leading)
                                .focusSection()
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            if !showSidebar || subscriptions.count <= 1 {
                                tvOSViewOptionsButton
                            }

                            Group {
                                switch layout {
                                case .list:
                                    listContent
                                case .grid:
                                    gridContent
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .focusSection()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    #elseif os(macOS)
                    HStack(spacing: 0) {
                        if showSidebar && subscriptionsLoaded && subscriptions.count > 1 {
                            macOSChannelsSidebar
                                .frame(width: clampedMacOSSidebarWidth)

                            macOSSidebarResizeHandle
                        } else if showSidebar && !subscriptionsLoaded && sidebarExpected {
                            macOSSidebarPlaceholder
                                .frame(width: clampedMacOSSidebarWidth)

                            macOSSidebarResizeHandle
                        }

                        Group {
                            switch layout {
                            case .list:
                                listContent
                            case .grid:
                                gridContent
                            }
                        }
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                    }
                    #else
                    if isIPadRegular && showSidebar && subscriptionsLoaded && subscriptions.count > 1 {
                        HStack(spacing: 0) {
                            iOSChannelsSidebar
                                .frame(width: clampedIPadSidebarWidth)

                            iPadSidebarResizeHandle

                            feedLayout
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .refreshable {
                            guard let appEnvironment else { return }
                            LoggingService.shared.info("User initiated pull-to-refresh in Subscriptions view", category: .general)
                            await loadSubscriptionsAsync()
                            await feedCache.refresh(using: appEnvironment)
                            LoggingService.shared.info("Pull-to-refresh completed", category: .general)
                        }
                    } else {
                        feedLayout
                            .refreshable {
                                guard let appEnvironment else { return }
                                LoggingService.shared.info("User initiated pull-to-refresh in Subscriptions view", category: .general)
                                await loadSubscriptionsAsync()
                                await feedCache.refresh(using: appEnvironment)
                                LoggingService.shared.info("Pull-to-refresh completed", category: .general)
                            }
                    }
                    #endif

                    // Bottom overlay for filter strip (iOS only, compact width)
                    #if os(iOS)
                    VStack {
                        Spacer()

                        if subscriptionsLoaded && subscriptions.count > 1 && channelStripSize != .disabled && !isShowingFullScreenError && !(isIPadRegular && showSidebar) {
                            bottomFloatingFilterStrip
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    #endif
                }
                // Above the feed rather than inside it: the feed is local data
                // while this is showing, and nothing else on screen says so.
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let unavailability = contextUnavailability {
                        DataContextUnavailableBanner(reason: unavailability)
                    }
                }
                #if !os(tvOS)
                .navigationTitle(String(localized: "tabs.subscriptions"))
                #if os(iOS)
                .toolbarTitleDisplayMode(isIPadRegular ? .inline : .inlineLarge)
                #else
                .toolbarTitleDisplayMode(.inlineLarge)
                #endif
                .toolbar {
                    if appEnvironment?.settingsManager.showAccountPickers ?? true {
                        ToolbarItem(placement: viewOptionsPlacement) {
                            DataContextSwitcherMenu()
                        }
                    }
                    ToolbarItem(placement: viewOptionsPlacement) {
                        Button {
                            showViewOptions = true
                        } label: {
                            Label(String(localized: "viewOptions.title"), systemImage: "slider.horizontal.3")
                        }
                        .liquidGlassTransitionSource(id: "subscriptionsViewOptions", in: sheetTransition)
                        #if os(macOS)
                        .popover(isPresented: $showViewOptions, arrowEdge: .bottom) {
                            viewOptionsForm
                                .padding()
                                .frame(width: 300)
                                .onDisappear {
                                    // Present the sheet only after the popover is gone,
                                    // otherwise the presentation is swallowed.
                                    if pendingSubscriptionsData {
                                        pendingSubscriptionsData = false
                                        showSubscriptionsData = true
                                    }
                                }
                        }
                        #endif
                    }
                }
                #endif
                #if os(macOS)
                .sheet(isPresented: $showSubscriptionsData) {
                    subscriptionsDataSheet
                }
                #else
                .sheet(isPresented: $showViewOptions) {
                        NavigationStack {
                            viewOptionsForm
                            #if os(tvOS)
                            .scrollClipDisabled()
                            .padding(.horizontal, 40)
                            .padding(.vertical, 24)
                            #else
                            .navigationTitle(String(localized: "subscriptions.viewOptions.title"))
                            #if os(iOS)
                            .navigationBarTitleDisplayMode(.inline)
                            #endif
                            #endif
                        }
                        .presentationDetents([.height(520), .large])
                        .presentationDragIndicator(.visible)
                        .liquidGlassSheetContent(sourceID: "subscriptionsViewOptions", in: sheetTransition)
                    }
                    #endif
                    .onAppear {
                        // Synchronous load for local accounts so the sidebar is
                        // present in the first layout pass (avoids layout jump).
                        loadSubscriptions()
                        // Coming back to a feed that failed while it was away is
                        // the most likely moment for it to work again.
                        retryFeedIfNeeded()
                    }
                    .onChange(of: scenePhase) { _, phase in
                        guard phase == .active else { return }
                        retryFeedIfNeeded()
                    }
                    .task {
                        await loadSubscriptionsAsync()
                        loadWatchEntries()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .subscriptionsDidChange)) { _ in
                        Task {
                            await loadSubscriptionsAsync()
                        }
                        // Subscription changes now trigger a full refresh via invalidation
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
                        loadWatchEntries()
                    }
                    // The data context, not the legacy setting: two logins on
                    // the same instance map onto the same legacy value, so
                    // switching between them would change nothing here and this
                    // view would keep showing the first account's subscriptions
                    // while writes went to the second.
                    //
                    // Status changes count too, through the *effective* context:
                    // a credential arriving or being rejected moves reads
                    // between the account and local without the stored context
                    // moving at all.
                    .onReceive(NotificationCenter.default.publisher(for: .dataContextDidChange)) { _ in
                        reloadForContextChange()
                    }
                    // Instances count for the same reason: switching one off
                    // moves reads to local without touching the stored context
                    // or any account status. And a status that lifts without
                    // moving reads at all still deserves the attempt the
                    // failure before it never got.
                    .onReceive(NotificationCenter.default.publisher(for: .accountStatusesDidChange)) { _ in
                        guard !reloadIfEffectiveContextMoved() else { return }
                        retryFeedIfNeeded()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .instancesDidChange)) { _ in
                        reloadIfEffectiveContextMoved()
                    }
                    // Signing in again keeps the same account and context, so
                    // nothing above would fire — but the data on screen may now
                    // belong to a different person on that server.
                    .onReceive(NotificationCenter.default.publisher(for: .accountCredentialDidChange)) { _ in
                        reloadForContextChange()
                    }
                .task(id: instanceConfigurationID) {
                    LoggingService.shared.debug("SubscriptionsView task triggered, instanceConfigurationID: \(instanceConfigurationID)", category: .general)
                    await loadSubscriptionsAsync()

                    await feedCache.loadFromDiskIfNeeded()

                    let hasYatteeServer = appEnvironment?.instancesManager.instances.contains {
                        $0.type == .yatteeServer && $0.isEnabled
                    } ?? false

                    let cacheValid = feedCache.isCacheValid(using: appEnvironment?.settingsManager)
                    LoggingService.shared.debug(
                        "hasYatteeServer: \(hasYatteeServer), cacheValid: \(cacheValid), isLoading: \(feedCache.isLoading)",
                        category: .general
                    )

                    if hasYatteeServer {
                        LoggingService.shared.info("Yattee Server detected, forcing feed refresh", category: .general)
                        await loadFeed(forceRefresh: true)
                    } else if !cacheValid && !feedCache.isLoading {
                        LoggingService.shared.info("Cache invalid and not loading, refreshing feed", category: .general)
                        await loadFeed(forceRefresh: false)
                    } else {
                        LoggingService.shared.debug("Using cached feed, no refresh needed", category: .general)
                    }
                }
                // A server that went away comes back without announcing it, and
                // a feed that failed on the way to it is not watching anything
                // that would notice — so it asks again on its own, for as long
                // as the failure is on screen.
                //
                // One attempt in flight at a time, and none at all outside the
                // states above: the id going nil, the fence dropping the state
                // back to idle, and the view disappearing all cancel this task,
                // and the next attempt is only armed by the last one finishing.
                .task(id: feedRetryToken) {
                    guard feedRetryToken != nil else { return }
                    try? await Task.sleep(for: .seconds(Self.feedRetryInterval))
                    guard !Task.isCancelled else { return }
                    await loadFeed(forceRefresh: true)
                    feedRetryAttempt += 1
                }
                .onChange(of: selectedChannelID) { _, _ in
                    withAnimation {
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
                #if os(tvOS)
                .onChange(of: filteredVideos.first?.id.videoID, initial: true) { _, newValue in
                    // Work around tvOS ScrollView + prefersDefaultFocus bug: set initial focus
                    // (and refocus after channel filter changes) to the first video once cells materialize.
                    guard let newValue else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        focusedVideoID = newValue
                    }
                }
                #endif
            }
            .onChange(of: geometry.size.width, initial: true) { _, newWidth in
                viewWidth = newWidth
            }
        }
    }

    // MARK: - List Layout

    private var listContent: some View {
        VideoListContainer(listStyle: listStyle, rowStyle: rowStyle) {
            // Header: status banner with scroll anchor
            feedStatusBanner
                .id("top")

            // Section header (channel link is shown in the inline header on tvOS)
            #if !os(tvOS)
            sectionHeaderView
            #endif
        } content: {
            feedContentRows
        } footer: {
            #if os(iOS)
            // Bottom spacer for channel strip overlay (outside the card)
            if channelStripSize != .disabled && subscriptions.count > 1 && !isShowingFullScreenError {
                Color.clear.frame(height: channelStripSize.totalHeight)
            }
            #else
            EmptyView()
            #endif
        }
    }

    /// Section header with proper padding for list style.
    private var sectionHeaderView: some View {
        HStack {
            feedSectionHeader
            Spacer()
        }
        .padding(.horizontal, listStyle == .inset ? 32 : 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    /// Feed content rows or empty/loading states.
    @ViewBuilder
    private var feedContentRows: some View {
        if let feedError = displayedFeedError, feedCache.videos.isEmpty {
            // Show specific error states
            switch feedError {
            case .yatteeServerRequired:
                yatteeServerRequiredView
            case .notAuthenticated:
                notAuthenticatedView
            case .networkError(let message):
                gridErrorView(message)
            }
        } else if feedCache.isLoading && feedCache.videos.isEmpty {
            gridLoadingView
        } else if let error = errorMessage, feedCache.videos.isEmpty {
            gridErrorView(error)
        } else if !feedCache.videos.isEmpty {
            if filteredVideos.isEmpty && selectedChannelID != nil {
                ContentUnavailableView {
                    Label(String(localized: "subscriptions.noVideosFromChannel"), systemImage: "video.slash")
                } description: {
                    Text(String(localized: "subscriptions.noVideosFromChannel.description"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(Array(filteredVideos.enumerated()), id: \.element.id) { index, video in
                    VideoListRow(
                        isLast: index == filteredVideos.count - 1,
                        rowStyle: rowStyle,
                        listStyle: listStyle
                    ) {
                        VideoRowView(
                            video: video,
                            style: rowStyle,
                            watchProgress: watchProgress(for: video)
                        )
                        .tappableVideo(
                            video,
                            queueSource: subscriptionsQueueSource,
                            sourceLabel: String(localized: "queue.source.subscriptions"),
                            videoList: filteredVideos,
                            videoIndex: index,
                            loadMoreVideos: loadMoreSubscriptionsCallback
                        )
                    }
                    #if os(tvOS)
                    .focused($focusedVideoID, equals: video.id.videoID)
                    #else
                    .videoSwipeActions(video: video)
                    #endif
                }

                // Infinite scroll trigger for Invidious feed
                if feedCache.hasMorePages && !feedCache.isLoading {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task {
                                guard let appEnvironment else { return }
                                await feedCache.loadMoreInvidiousFeed(using: appEnvironment)
                            }
                        }
                }
            }
        } else if feedSettledOnAnsweredError {
            feedUnavailableView
        } else if feedCache.hasLoadedOnce {
            gridEmptyView
        } else {
            gridLoadingView
        }
    }

    // MARK: - Grid Layout

    private var gridContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                feedStatusBanner
                    .id("top")

                // Section header (channel link is shown in the inline header on tvOS)
                #if !os(tvOS)
                HStack {
                    feedSectionHeader
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)
                #endif

                // Content
                if let feedError = displayedFeedError, feedCache.videos.isEmpty {
                    // Show specific error states
                    switch feedError {
                    case .yatteeServerRequired:
                        yatteeServerRequiredView
                    case .notAuthenticated:
                        notAuthenticatedView
                    case .networkError(let message):
                        gridErrorView(message)
                    }
                } else if feedCache.isLoading && feedCache.videos.isEmpty {
                    gridLoadingView
                } else if let error = errorMessage, feedCache.videos.isEmpty {
                    gridErrorView(error)
                } else if !feedCache.videos.isEmpty {
                    gridFeedContent
                } else if feedSettledOnAnsweredError {
                    feedUnavailableView
                } else if feedCache.hasLoadedOnce {
                    gridEmptyView
                } else {
                    gridLoadingView
                }

                // Bottom spacer for channel strip overlay
                if channelStripSize != .disabled && subscriptions.count > 1 && !isShowingFullScreenError {
                    Color.clear.frame(height: channelStripSize.totalHeight)
                }
            }
        }
        #if os(tvOS)
        .scrollClipDisabled()
        #endif
    }

    // MARK: - Channel Filter Strip

    private var bottomFloatingFilterStrip: some View {
        ViewThatFits(in: .horizontal) {
            // Option 1: Non-scrolling centered layout (used when all chips fit)
            channelChipsHStack
                .padding(.horizontal, 12)
                .padding(.vertical, channelStripSize.verticalPadding)
                .clipShape(Capsule())
                #if os(tvOS)
                .background(Color.black.opacity(0.3))
                #else
                .glassBackground(.regular, in: .capsule, fallback: .regularMaterial)
                #endif

            // Option 2: Scrollable layout (used when chips overflow)
            ScrollView(.horizontal, showsIndicators: false) {
                channelChipsHStack
                    .padding(.horizontal, 12)
                    .padding(.vertical, channelStripSize.verticalPadding)
            }
            .clipShape(Capsule())
            #if os(tvOS)
            .background(Color.black.opacity(0.3))
            #else
            .glassBackground(.regular, in: .capsule, fallback: .regularMaterial)
            #endif
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// The HStack containing channel filter chips (extracted to avoid duplication).
    private var channelChipsHStack: some View {
        HStack(spacing: channelStripSize.chipSpacing) {
            ForEach(sortedSubscriptions, id: \.channelID) { subscription in
                ChannelFilterChip(
                    channelID: subscription.channelID,
                    name: subscription.name,
                    avatarURL: subscription.avatarURL,
                    serverURL: yatteeServerURL,
                    isSelected: selectedChannelID == subscription.channelID,
                    avatarSize: channelStripSize.avatarSize,
                    onTap: {
                        if selectedChannelID == subscription.channelID {
                            selectedChannelID = nil
                        } else {
                            selectedChannelID = subscription.channelID
                        }
                    },
                    onGoToChannel: {
                        appEnvironment?.navigationCoordinator.navigate(
                            to: .channel(subscription.channelID, subscription.contentSource)
                        )
                    },
                    onUnsubscribe: {
                        unsubscribeChannel(subscription.channelID)
                    },
                    authHeader: yatteeServerAuthHeader
                )
            }
        }
    }

    // MARK: - tvOS Channels Sidebar

    #if os(tvOS)
    private var tvOSViewOptionsButton: some View {
        HStack(spacing: 16) {
            Button {
                showViewOptions = true
            } label: {
                Label(String(localized: "viewOptions.title"), systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)

            if appEnvironment?.settingsManager.showAccountPickers ?? true {
                DataContextSwitcherButton()
            }
        }
    }

    private var tvOSChannelsSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            tvOSViewOptionsButton
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 20) {
                    TVSubscriptionsSidebarRow(
                        name: String(localized: "subscriptions.allChannels"),
                        avatarURL: nil,
                        serverURL: nil,
                        authHeader: nil,
                        channelID: nil,
                        isAllChannels: true,
                        isSelected: selectedChannelID == nil,
                        onTap: {
                            if selectedChannelID != nil {
                                selectedChannelID = nil
                            }
                        }
                    )
                    .contextMenu {
                        Button {
                            appEnvironment?.navigationCoordinator.navigate(to: .manageChannels)
                        } label: {
                            Label(String(localized: "sidebar.manageChannels"), systemImage: "person.2.badge.gearshape")
                        }
                    }

                    ForEach(sortedSubscriptions, id: \.channelID) { subscription in
                        TVSubscriptionsSidebarRow(
                            name: subscription.name,
                            avatarURL: subscription.avatarURL,
                            serverURL: yatteeServerURL,
                            authHeader: yatteeServerAuthHeader,
                            channelID: subscription.channelID,
                            isAllChannels: false,
                            isSelected: selectedChannelID == subscription.channelID,
                            onTap: {
                                if selectedChannelID == subscription.channelID {
                                    selectedChannelID = nil
                                } else {
                                    selectedChannelID = subscription.channelID
                                }
                            }
                        )
                        .contextMenu {
                            Button {
                                appEnvironment?.navigationCoordinator.navigate(
                                    to: .channel(subscription.channelID, subscription.contentSource)
                                )
                            } label: {
                                Label(String(localized: "subscriptions.goToChannel"), systemImage: "person.circle")
                            }
                            Button(role: .destructive) {
                                unsubscribeChannel(subscription.channelID)
                            } label: {
                                Label(String(localized: "channel.unsubscribe"), systemImage: "person.badge.minus")
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
            }
            .scrollClipDisabled()
        }
    }
    #endif

    // MARK: - Channels Sidebar (macOS / iPad)

    #if !os(tvOS)
    private static let sidebarAllChannelsTag = "__all__"

    private var sidebarSelection: Binding<String?> {
        Binding(
            get: { selectedChannelID ?? Self.sidebarAllChannelsTag },
            set: { newValue in
                selectedChannelID = (newValue == Self.sidebarAllChannelsTag) ? nil : newValue
            }
        )
    }

    @ViewBuilder
    private var channelsSidebarContent: some View {
        SubscriptionsSidebarRow(
            name: String(localized: "subscriptions.allChannels"),
            avatarURL: nil,
            serverURL: nil,
            authHeader: nil,
            channelID: nil,
            isAllChannels: true
        )
        .tag(Self.sidebarAllChannelsTag)
        .contextMenu {
            Button {
                appEnvironment?.navigationCoordinator.navigate(to: .manageChannels)
            } label: {
                Label(String(localized: "sidebar.manageChannels"), systemImage: "person.2.badge.gearshape")
            }
        }

        ForEach(sortedSubscriptions, id: \.channelID) { subscription in
            SubscriptionsSidebarRow(
                name: subscription.name,
                avatarURL: subscription.avatarURL,
                serverURL: yatteeServerURL,
                authHeader: yatteeServerAuthHeader,
                channelID: subscription.channelID,
                isAllChannels: false
            )
            .tag(Optional(subscription.channelID))
            .contextMenu {
                Button {
                    appEnvironment?.navigationCoordinator.navigate(
                        to: .channel(subscription.channelID, subscription.contentSource)
                    )
                } label: {
                    Label(String(localized: "subscriptions.goToChannel"), systemImage: "person.circle")
                }
                Button(role: .destructive) {
                    unsubscribeChannel(subscription.channelID)
                } label: {
                    Label(String(localized: "channel.unsubscribe"), systemImage: "person.badge.minus")
                }
            }
        }
    }
    #endif

    #if os(macOS)
    private static let macOSSidebarMinWidth = 180.0
    private static let macOSSidebarMaxWidth = 400.0

    private var clampedMacOSSidebarWidth: CGFloat {
        CGFloat(min(max(macOSSidebarWidth, Self.macOSSidebarMinWidth), Self.macOSSidebarMaxWidth))
    }

    private var macOSChannelsSidebar: some View {
        List(selection: sidebarSelection) {
            channelsSidebarContent
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private var macOSSidebarPlaceholder: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var macOSSidebarResizeHandle: some View {
        ZStack {
            Rectangle()
                .fill(.separator.opacity(0.6))
                .frame(width: 1)

            Rectangle()
                .fill(.clear)
                .frame(width: 8)
                .contentShape(Rectangle())
        }
        .frame(width: 8)
        .frame(maxHeight: .infinity)
        .background(.clear)
        .contentShape(Rectangle())
        .highPriorityGesture(macOSSidebarResizeGesture)
        .onHover { isHovering in
            if isHovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var macOSSidebarResizeGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if macOSSidebarDragStartWidth == nil {
                    macOSSidebarDragStartWidth = macOSSidebarWidth
                }

                let baseWidth = macOSSidebarDragStartWidth ?? macOSSidebarWidth
                let newWidth = baseWidth + value.translation.width
                macOSSidebarWidth = min(max(newWidth, Self.macOSSidebarMinWidth), Self.macOSSidebarMaxWidth)
            }
            .onEnded { _ in
                macOSSidebarDragStartWidth = nil
            }
    }
    #endif

    private var isSidebarVisible: Bool {
        #if os(macOS)
        return showSidebar && subscriptionsLoaded && subscriptions.count > 1
        #elseif os(iOS)
        return isIPadRegular && showSidebar && subscriptionsLoaded && subscriptions.count > 1
        #elseif os(tvOS)
        return showSidebar && subscriptionsLoaded && subscriptions.count > 1
        #else
        return false
        #endif
    }

    #if os(iOS)
    private static let iPadSidebarMinWidth = 220.0
    private static let iPadSidebarMaxWidth = 420.0

    private var isIPadRegular: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var clampedIPadSidebarWidth: CGFloat {
        CGFloat(min(max(iPadSidebarWidth, Self.iPadSidebarMinWidth), Self.iPadSidebarMaxWidth))
    }

    @ViewBuilder
    private var feedLayout: some View {
        Group {
            switch layout {
            case .list:
                listContent
            case .grid:
                gridContent
            }
        }
    }

    private var iOSChannelsSidebar: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                iOSSidebarRow(
                    name: String(localized: "subscriptions.allChannels"),
                    avatarURL: nil,
                    serverURL: nil,
                    authHeader: nil,
                    channelID: nil,
                    isAllChannels: true,
                    isSelected: selectedChannelID == nil
                ) {
                    if selectedChannelID != nil { selectedChannelID = nil }
                }
                .contextMenu {
                    Button {
                        appEnvironment?.navigationCoordinator.navigate(to: .manageChannels)
                    } label: {
                        Label(String(localized: "sidebar.manageChannels"), systemImage: "person.2.badge.gearshape")
                    }
                }

                ForEach(sortedSubscriptions, id: \.channelID) { subscription in
                    iOSSidebarRow(
                        name: subscription.name,
                        avatarURL: subscription.avatarURL,
                        serverURL: yatteeServerURL,
                        authHeader: yatteeServerAuthHeader,
                        channelID: subscription.channelID,
                        isAllChannels: false,
                        isSelected: selectedChannelID == subscription.channelID
                    ) {
                        if selectedChannelID == subscription.channelID {
                            selectedChannelID = nil
                        } else {
                            selectedChannelID = subscription.channelID
                        }
                    }
                    .contextMenu {
                        Button {
                            appEnvironment?.navigationCoordinator.navigate(
                                to: .channel(subscription.channelID, subscription.contentSource)
                            )
                        } label: {
                            Label(String(localized: "subscriptions.goToChannel"), systemImage: "person.circle")
                        }
                        Button(role: .destructive) {
                            unsubscribeChannel(subscription.channelID)
                        } label: {
                            Label(String(localized: "channel.unsubscribe"), systemImage: "person.badge.minus")
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var iPadSidebarResizeHandle: some View {
        if isIPadRegular {
            Rectangle()
                .fill(.separator.opacity(0.7))
                .frame(width: 1)
            .frame(width: 14)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(iPadSidebarResizeGesture)
        }
    }

    private var iPadSidebarResizeGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if iPadSidebarDragStartWidth == nil {
                    iPadSidebarDragStartWidth = iPadSidebarWidth
                }

                let baseWidth = iPadSidebarDragStartWidth ?? iPadSidebarWidth
                let newWidth = baseWidth + value.translation.width
                iPadSidebarWidth = min(max(newWidth, Self.iPadSidebarMinWidth), Self.iPadSidebarMaxWidth)
            }
            .onEnded { _ in
                iPadSidebarDragStartWidth = nil
            }
    }

    @ViewBuilder
    private func iOSSidebarRow(
        name: String,
        avatarURL: URL?,
        serverURL: URL?,
        authHeader: String?,
        channelID: String?,
        isAllChannels: Bool,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SubscriptionsSidebarRow(
                name: name,
                avatarURL: avatarURL,
                serverURL: serverURL,
                authHeader: authHeader,
                channelID: channelID,
                isAllChannels: isAllChannels,
                isSelected: isSelected
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? accentColor.opacity(0.2) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    #endif

    // MARK: - Content Views

    private var subscriptionsQueueSource: QueueSource {
        .subscriptions(continuation: nil)
    }

    @ViewBuilder
    private var gridFeedContent: some View {
        if filteredVideos.isEmpty && selectedChannelID != nil {
            ContentUnavailableView {
                Label(String(localized: "subscriptions.noVideosFromChannel"), systemImage: "video.slash")
            } description: {
                Text(String(localized: "subscriptions.noVideosFromChannel.description"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 40)
        } else {
            VideoGridContent(columns: gridConfig.effectiveColumns) {
                ForEach(Array(filteredVideos.enumerated()), id: \.element.id) { index, video in
                    VideoCardView(
                        video: video,
                        watchProgress: watchProgress(for: video),
                        isCompact: gridConfig.isCompactCards
                    )
                    .tappableVideo(
                        video,
                        queueSource: subscriptionsQueueSource,
                        sourceLabel: String(localized: "queue.source.subscriptions"),
                        videoList: filteredVideos,
                        videoIndex: index,
                        loadMoreVideos: loadMoreSubscriptionsCallback
                    )
                    #if os(tvOS)
                    .focused($focusedVideoID, equals: video.id.videoID)
                    #endif
                }
            }

            // Infinite scroll trigger for Invidious feed
            if feedCache.hasMorePages && !feedCache.isLoading {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        Task {
                            guard let appEnvironment else { return }
                            await feedCache.loadMoreInvidiousFeed(using: appEnvironment)
                        }
                    }
            }
        }
    }

    private var feedSectionHeader: some View {
        HStack {
            feedSectionHeaderLabel
            Spacer()
        }
    }

    @ViewBuilder
    private var feedSectionHeaderLabel: some View {
        if feedCache.isLoading, let progress = feedCache.loadingProgress {
            Text("subscriptions.updatingChannels \(progress.loaded) \(progress.total)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } else if isSidebarVisible {
            EmptyView()
        } else if let subscription = selectedSubscription {
            Button {
                appEnvironment?.navigationCoordinator.navigate(
                    to: .channel(subscription.channelID, subscription.contentSource)
                )
            } label: {
                HStack(spacing: 4) {
                    Text(subscription.name)
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .foregroundStyle(accentColor)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: NavigationDestination.manageChannels) {
                HStack(spacing: 4) {
                    Text(String(localized: "subscriptions.allChannels"))
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .foregroundStyle(accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading/Error/Empty Views

    private var gridLoadingView: some View {
        VStack(spacing: 16) {
            ProgressView()

            if let progress = feedCache.loadingProgress {
                Text(verbatim: "\(progress.loaded)/\(progress.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var gridEmptyView: some View {
        ContentUnavailableView {
            Label(String(localized: "subscriptions.feed.title"), systemImage: "play.rectangle.on.rectangle")
        } description: {
            Text(String(localized: "subscriptions.empty.description"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    /// Empty state shown when Yattee Server is required but not configured.
    private var yatteeServerRequiredView: some View {
        ContentUnavailableView {
            Label(String(localized: "subscriptions.yatteeServerRequired.title"), systemImage: "server.rack")
        } description: {
            Text(String(localized: "subscriptions.yatteeServerRequired.description"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    /// Terminal state for a feed that stopped on a failure the banner explains.
    private var feedUnavailableView: some View {
        ContentUnavailableView {
            Label(String(localized: "subscriptions.feedUnavailable.title"), systemImage: "wifi.exclamationmark")
        } description: {
            Text(String(localized: "subscriptions.feedUnavailable.description"))
        } actions: {
            Button(String(localized: "common.retry")) {
                Task { await loadFeed(forceRefresh: true) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    /// Empty state shown when Invidious account is not authenticated.
    private var notAuthenticatedView: some View {
        ContentUnavailableView {
            Label(String(localized: "subscriptions.notAuthenticated.title"), systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text(String(localized: "subscriptions.notAuthenticated.description"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    private func gridErrorView(_ error: String) -> some View {
        ContentUnavailableView {
            Label(String(localized: "common.error"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button(String(localized: "common.retry")) {
                Task { await loadFeed(forceRefresh: true) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Data Loading

    private func loadSubscriptions() {
        // For local account, load from DataManager
        // For Invidious, subscriptions will be loaded async in loadSubscriptionsAsync
        if appEnvironment?.accountsManager.currentContext.isLocal == true {
            subscriptions = dataManager?.subscriptions() ?? []
            subscriptionsLoaded = true
            sidebarExpected = subscriptions.count > 1
        }

        if let selectedID = selectedChannelID,
           !subscriptions.contains(where: { $0.channelID == selectedID }) {
            selectedChannelID = nil
        }
    }

    /// Loads subscriptions asynchronously from the current provider.
    /// For Invidious, this fetches from the API and creates temporary Subscription objects for UI.
    @discardableResult
    private func reloadIfEffectiveContextMoved() -> Bool {
        guard appEnvironment?.dataContextValidator.effectiveContext != loadedContext else { return false }
        reloadForEffectiveContextChange()
        return true
    }

    /// Drops what is on screen and reloads it for whatever context is current.
    private func reloadForContextChange() {
        feedCache.handleAccountChange()
        subscriptions = []
        subscriptionsLoaded = false
        reload()
    }

    /// Reloads for a move the user did not make — a status lifting or falling,
    /// an instance switched off — where the selection itself is unchanged.
    ///
    /// Keeps what is on screen: the cached feed and the channel list still
    /// belong to the account that was selected before and still is, and they
    /// are the fallback the banner is telling the user they are looking at.
    private func reloadForEffectiveContextChange() {
        feedCache.handleEffectiveContextChange()
        reload()
    }

    private func reload() {
        loadedContext = appEnvironment?.dataContextValidator.effectiveContext

        Task {
            guard let appEnvironment else { return }
            await loadSubscriptionsAsync()
            await feedCache.refresh(using: appEnvironment)
        }
    }

    /// Tries the feed again when something happened that may have changed the
    /// answer, and it is sitting on a failure.
    ///
    /// The account statuses lift on their own, but a feed that already failed
    /// has nothing watching for that — it waited for a Retry nobody should have
    /// to press to find out the server came back.
    private func retryFeedIfNeeded() {
        guard case .error = feedCache.feedLoadState, !feedCache.isLoading else { return }
        Task { await loadFeed(forceRefresh: true) }
    }

    private func loadSubscriptionsAsync() async {
        guard let subscriptionService, let appEnvironment else { return }

        // Recorded on every load, not only on a context change: the first load
        // of a session has to establish what is on screen, or the first status
        // change would look like a move and reload for nothing.
        loadedContext = appEnvironment.dataContextValidator.effectiveContext

        // For local account, just load from DataManager (fast)
        if appEnvironment.accountsManager.currentContext.isLocal {
            subscriptions = dataManager?.subscriptions() ?? []
            subscriptionsLoaded = true
            sidebarExpected = subscriptions.count > 1
            return
        }

        // For Invidious, fetch from API
        do {
            let channels = try await subscriptionService.fetchSubscriptions()
            // Convert channels to Subscription objects for UI (not persisted)
            subscriptions = channels.map { Subscription.from(channel: $0) }
            subscriptionsLoaded = true
            sidebarExpected = subscriptions.count > 1
        } catch {
            LoggingService.shared.error(
                "Failed to load subscriptions: \(error.localizedDescription)",
                category: .general
            )
            subscriptions = []
            subscriptionsLoaded = true
            sidebarExpected = false
        }
    }

    private func loadWatchEntries() {
        watchEntriesMap = dataManager?.watchEntriesMap() ?? [:]
    }

    private func loadFeed(forceRefresh: Bool) async {
        guard let appEnvironment else { return }

        if !forceRefresh && feedCache.isCacheValid(using: appEnvironment.settingsManager) {
            return
        }

        errorMessage = nil
        await feedCache.refresh(using: appEnvironment)
    }

    private func unsubscribeChannel(_ channelID: String) {
        Task {
            do {
                try await subscriptionService?.unsubscribe(from: channelID)
                // Remove from local list immediately for responsiveness
                subscriptions.removeAll { $0.channelID == channelID }
            } catch {
                LoggingService.shared.error(
                    "Failed to unsubscribe: \(error.localizedDescription)",
                    category: .general
                )
            }
        }
    }

    @Sendable
    private func loadMoreSubscriptionsCallback() async throws -> ([Video], String?) {
        return ([], nil)
    }
}

// MARK: - Preview

#Preview("With Subscriptions") {
    PreviewWrapper()
}

private struct PreviewWrapper: View {
    let dataManager: DataManager
    let previewEnvironment: AppEnvironment

    init() {
        let dataManager = try! DataManager.preview()

        let channel1 = Channel(
            id: ChannelID(source: .global(provider: ContentSource.youtubeProvider), channelID: "UC1"),
            name: "Apple Developer",
            thumbnailURL: nil
        )
        let channel2 = Channel(
            id: ChannelID(source: .global(provider: ContentSource.youtubeProvider), channelID: "UC2"),
            name: "Marques Brownlee",
            thumbnailURL: nil
        )
        let channel3 = Channel(
            id: ChannelID(source: .global(provider: ContentSource.youtubeProvider), channelID: "UC3"),
            name: "Music Channel",
            thumbnailURL: nil
        )

        dataManager.subscribe(to: channel1)
        dataManager.subscribe(to: channel2)
        dataManager.subscribe(to: channel3)

        self.dataManager = dataManager
        self.previewEnvironment = AppEnvironment(dataManager: dataManager)

        let cache = SubscriptionFeedCache.shared
        cache.videos = [
            Video(
                id: VideoID(source: .global(provider: ContentSource.youtubeProvider), videoID: "video1"),
                title: "SwiftUI Tutorial: Building Amazing Apps",
                description: "Learn how to build amazing apps with SwiftUI",
                author: Author(id: "UC1", name: "Apple Developer"),
                duration: 600,
                publishedAt: Date().addingTimeInterval(-3600),
                publishedText: "1 hour ago",
                viewCount: 10000,
                likeCount: 500,
                thumbnails: [],
                isLive: false,
                isUpcoming: false,
                scheduledStartTime: nil
            ),
            Video(
                id: VideoID(source: .global(provider: ContentSource.youtubeProvider), videoID: "video2"),
                title: "Tech Review: Latest Innovations",
                description: "Reviewing the latest tech innovations",
                author: Author(id: "UC2", name: "Marques Brownlee"),
                duration: 900,
                publishedAt: Date().addingTimeInterval(-7200),
                publishedText: "2 hours ago",
                viewCount: 50000,
                likeCount: 2000,
                thumbnails: [],
                isLive: false,
                isUpcoming: false,
                scheduledStartTime: nil
            ),
            Video(
                id: VideoID(source: .global(provider: ContentSource.youtubeProvider), videoID: "video3"),
                title: "Music Production Tips and Tricks",
                description: "Professional music production techniques",
                author: Author(id: "UC3", name: "Music Channel"),
                duration: 450,
                publishedAt: Date().addingTimeInterval(-10800),
                publishedText: "3 hours ago",
                viewCount: 5000,
                likeCount: 250,
                thumbnails: [],
                isLive: false,
                isUpcoming: false,
                scheduledStartTime: nil
            )
        ]
        cache.hasLoadedOnce = true
        cache.lastUpdated = Date()
    }

    var body: some View {
        NavigationStack {
            SubscriptionsView()
        }
        .appEnvironment(previewEnvironment)
    }
}

#Preview("Empty") {
    NavigationStack {
        SubscriptionsView()
    }
    .appEnvironment(.preview)
}
