//
//  SubscriptionsView.swift
//  Yattee
//
//  Subscriptions tab with channel filter strip and feed.
//

import SwiftUI

struct SubscriptionsView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Namespace private var sheetTransition
    #if os(tvOS)
    @Namespace private var defaultFocusNamespace
    #endif
    @State private var feedCache = SubscriptionFeedCache.shared
    @State private var subscriptions: [Subscription] = []
    @State private var subscriptionsLoaded = false
    @State private var selectedChannelID: String? = nil
    @State private var errorMessage: String?
    @State private var watchEntriesMap: [String: WatchEntry] = [:]
    @State private var showViewOptions = false

    // View options (persisted)
    @AppStorage("subscriptionsLayout") private var layout: VideoListLayout = .list
    @AppStorage("subscriptionsRowStyle") private var rowStyle: VideoRowStyle = .regular
    @AppStorage("subscriptionsGridColumns") private var gridColumns = 2
    @AppStorage("subscriptionsHideWatched") private var hideWatched = false
    @AppStorage("subscriptionsChannelStripSize") private var channelStripSize: ChannelStripSize = .normal

    /// List style from centralized settings.
    private var listStyle: VideoListStyle {
        appEnvironment?.settingsManager.listStyle ?? .inset
    }

    // Grid layout configuration
    @State private var viewWidth: CGFloat = 0
    private var gridConfig: GridLayoutConfiguration {
        GridLayoutConfiguration(viewWidth: viewWidth, gridColumns: gridColumns)
    }

    private var isShowingFullScreenError: Bool {
        if case .error = feedCache.feedLoadState, feedCache.videos.isEmpty {
            return true
        }
        return false
    }

    private var dataManager: DataManager? { appEnvironment?.dataManager }
    private var subscriptionService: SubscriptionService? { appEnvironment?.subscriptionService }
    private var accentColor: Color { appEnvironment?.settingsManager.accentColor.color ?? .accentColor }
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
            .map { "\($0.id):\($0.isEnabled):\($0.apiKey?.isEmpty == false)" }
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

        case .error(let error):
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

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ZStack {
                    #if os(tvOS)
                    Group {
                        switch layout {
                        case .list:
                            listContent
                        case .grid:
                            gridContent
                        }
                    }
                    .focusSection()
                    .prefersDefaultFocus(in: defaultFocusNamespace)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        HStack(spacing: 24) {
                            feedSectionHeaderLabel
                            Spacer()
                            Button {
                                showViewOptions = true
                            } label: {
                                Label(String(localized: "viewOptions.title"), systemImage: "slider.horizontal.3")
                            }
                        }
                        .focusSection()
                        .padding(.horizontal, 48)
                        .padding(.top, 40)
                        .padding(.bottom, 40)
                        .frame(maxWidth: .infinity)
                    }
                    .focusScope(defaultFocusNamespace)
                    #else
                    Group {
                        switch layout {
                        case .list:
                            listContent
                        case .grid:
                            gridContent
                        }
                    }
                    .refreshable {
                        guard let appEnvironment else { return }
                        LoggingService.shared.info("User initiated pull-to-refresh in Subscriptions view", category: .general)
                        await loadSubscriptionsAsync()
                        await feedCache.refresh(using: appEnvironment)
                        LoggingService.shared.info("Pull-to-refresh completed", category: .general)
                    }
                    #endif

                    // Bottom overlay for filter strip
                    #if !os(tvOS)
                    VStack {
                        Spacer()

                        if subscriptionsLoaded && subscriptions.count > 1 && channelStripSize != .disabled && !isShowingFullScreenError {
                            bottomFloatingFilterStrip
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    #endif
                }
                #if !os(tvOS)
                .navigationTitle(String(localized: "tabs.subscriptions"))
                .toolbarTitleDisplayMode(.inlineLarge)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showViewOptions = true
                        } label: {
                            Label(String(localized: "viewOptions.title"), systemImage: "slider.horizontal.3")
                        }
                        .liquidGlassTransitionSource(id: "subscriptionsViewOptions", in: sheetTransition)
                    }
                }
                #endif
                .sheet(isPresented: $showViewOptions) {
                        NavigationStack {
                            Form {
                                Section {
                                    // Layout picker (segmented)
                                    Picker(selection: $layout) {
                                        ForEach(VideoListLayout.allCases, id: \.self) { option in
                                            Label(option.displayName, systemImage: option.systemImage)
                                                .tag(option)
                                        }
                                    } label: {
                                        Text("viewOptions.layout")
                                    }
                                    .pickerStyle(.segmented)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                                    // List-specific options
                                    if layout == .list {
                                        Picker("viewOptions.rowSize", selection: $rowStyle) {
                                            Text("viewOptions.rowSize.compact").tag(VideoRowStyle.compact)
                                            Text("viewOptions.rowSize.regular").tag(VideoRowStyle.regular)
                                            Text("viewOptions.rowSize.large").tag(VideoRowStyle.large)
                                        }
                                    }

                                    // Grid-specific options
                                    #if !os(tvOS)
                                    if layout == .grid {
                                        Stepper(
                                            "viewOptions.columns \(min(max(1, gridColumns), gridConfig.maxColumns))",
                                            value: $gridColumns,
                                            in: 1...gridConfig.maxColumns
                                        )
                                    }
                                    #endif

                                    Toggle("viewOptions.hideWatched", isOn: $hideWatched)

                                    Picker("viewOptions.channelStrip", selection: $channelStripSize) {
                                        ForEach(ChannelStripSize.allCases, id: \.self) { size in
                                            Text(size.displayName).tag(size)
                                        }
                                    }
                                }

                                #if !os(tvOS)
                                Section {
                                    NavigationLink {
                                        SubscriptionsSettingsView()
                                    } label: {
                                        Label(String(localized: "manageChannels.subscriptionsData"), systemImage: "person.2.badge.gearshape")
                                    }
                                }
                                #endif
                            }
                            .navigationTitle(String(localized: "subscriptions.viewOptions.title"))
                            #if os(iOS)
                            .navigationBarTitleDisplayMode(.inline)
                            #endif
                        }
                        .presentationDetents([.height(420), .large])
                        .presentationDragIndicator(.visible)
                        .liquidGlassSheetContent(sourceID: "subscriptionsViewOptions", in: sheetTransition)
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
                    .onChange(of: appEnvironment?.settingsManager.subscriptionAccount) { _, _ in
                        // Clear cache and refresh when subscription account changes
                        feedCache.handleAccountChange()
                        subscriptions = []
                        subscriptionsLoaded = false
                        Task {
                            guard let appEnvironment else { return }
                            await loadSubscriptionsAsync()
                            await feedCache.refresh(using: appEnvironment)
                        }
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
                .onChange(of: selectedChannelID) { _, _ in
                    withAnimation {
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
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
            // Bottom spacer for channel strip overlay (outside the card)
            if channelStripSize != .disabled && subscriptions.count > 1 && !isShowingFullScreenError {
                Color.clear.frame(height: channelStripSize.totalHeight)
            }
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
        if case .error(let feedError) = feedCache.feedLoadState, feedCache.videos.isEmpty {
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
                    #if !os(tvOS)
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
                if case .error(let feedError) = feedCache.feedLoadState, feedCache.videos.isEmpty {
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
                .foregroundStyle(Color.accentColor)
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
                .foregroundStyle(Color.accentColor)
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
        if appEnvironment?.settingsManager.subscriptionAccount.type == .local {
            subscriptions = dataManager?.subscriptions() ?? []
            subscriptionsLoaded = true
        }

        if let selectedID = selectedChannelID,
           !subscriptions.contains(where: { $0.channelID == selectedID }) {
            selectedChannelID = nil
        }
    }

    /// Loads subscriptions asynchronously from the current provider.
    /// For Invidious, this fetches from the API and creates temporary Subscription objects for UI.
    private func loadSubscriptionsAsync() async {
        guard let subscriptionService, let appEnvironment else { return }

        // For local account, just load from DataManager (fast)
        if appEnvironment.settingsManager.subscriptionAccount.type == .local {
            subscriptions = dataManager?.subscriptions() ?? []
            subscriptionsLoaded = true
            return
        }

        // For Invidious, fetch from API
        do {
            let channels = try await subscriptionService.fetchSubscriptions()
            // Convert channels to Subscription objects for UI (not persisted)
            subscriptions = channels.map { Subscription.from(channel: $0) }
            subscriptionsLoaded = true
        } catch {
            LoggingService.shared.error(
                "Failed to load subscriptions: \(error.localizedDescription)",
                category: .general
            )
            subscriptions = []
            subscriptionsLoaded = true
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
