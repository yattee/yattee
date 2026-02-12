//
//  ChannelView.swift
//  Yattee
//
//  Channel view with zoom/scale header and video grid.
//

import SwiftUI
import NukeUI

struct ChannelView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let channelID: String
    let source: ContentSource
    /// URL for external channel extraction (nil for YouTube/Invidious channels)
    var channelURL: URL? = nil

    /// Whether this is an external channel that requires extraction
    private var isExternalChannel: Bool {
        channelURL != nil
    }

    @Namespace private var sheetTransition
    @State private var channel: Channel?
    @State private var selectedTab: ChannelTab = .videos
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var subscription: Subscription?
    @State private var isSubscribed = false
    @State private var showingUnsubscribeConfirmation = false
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollToTop: Bool = false
    @State private var cachedHeader: CachedChannelData?

    // View options (persisted)
    @AppStorage("channel.layout") private var layout: VideoListLayout = .list
    @AppStorage("channel.rowStyle") private var rowStyle: VideoRowStyle = .regular
    @AppStorage("channel.gridColumns") private var gridColumns = 2
    @AppStorage("channel.hideWatched") private var hideWatched = false

    /// List style from centralized settings.
    private var listStyle: VideoListStyle {
        appEnvironment?.settingsManager.listStyle ?? .inset
    }

    // UI state for view options
    @State private var showViewOptions = false
    @State private var viewWidth: CGFloat = 0
    @State private var watchEntriesMap: [String: WatchEntry] = [:]

    // Videos tab state
    @State private var videos: [Video] = []
    @State private var videosContinuation: String?
    @State private var videosLoaded = false

    // Playlists tab state
    @State private var playlists: [Playlist] = []
    @State private var playlistsContinuation: String?
    @State private var playlistsLoaded = false

    // Shorts tab state
    @State private var shorts: [Video] = []
    @State private var shortsContinuation: String?
    @State private var shortsLoaded = false

    // Streams tab state
    @State private var streams: [Video] = []
    @State private var streamsContinuation: String?
    @State private var streamsLoaded = false

    // Search state
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var hasSearched = false  // True after user submits a search query
    @State private var searchResults: ChannelSearchPage = .empty
    @State private var isSearchLoading = false

    // External channel state (page-based pagination for extracted channels)
    @State private var externalCurrentPage = 1

    // Header configuration
    private let baseHeaderHeight: CGFloat = 280
    private let searchBarExtraHeight: CGFloat = 70
    private let collapsedHeaderHeight: CGFloat = 60
    private let avatarSize: CGFloat = 80
    private let collapsedAvatarSize: CGFloat = 36
    
    /// Whether search bar adjustments are needed (only on compact/iPhone where search bar overlays content)
    private var needsSearchBarAdjustment: Bool {
        supportsChannelSearch && horizontalSizeClass == .compact
    }
    
    /// Header height adjusted for search bar on iPhone (iOS 18+ places search bar in navigation area)
    private var headerHeight: CGFloat {
        baseHeaderHeight + (needsSearchBarAdjustment ? searchBarExtraHeight : 0)
    }

    private var accentColor: Color {
        appEnvironment?.settingsManager.accentColor.color ?? .accentColor
    }

    // Grid layout configuration
    private var gridConfig: GridLayoutConfiguration {
        GridLayoutConfiguration(viewWidth: viewWidth, gridColumns: gridColumns)
    }

    // Filtered video arrays (for hideWatched)
    private var filteredVideos: [Video] {
        hideWatched ? videos.filter { watchEntriesMap[$0.id.videoID]?.isFinished != true } : videos
    }

    private var filteredShorts: [Video] {
        hideWatched ? shorts.filter { watchEntriesMap[$0.id.videoID]?.isFinished != true } : shorts
    }

    private var filteredStreams: [Video] {
        hideWatched ? streams.filter { watchEntriesMap[$0.id.videoID]?.isFinished != true } : streams
    }

    /// Whether inset grouped background should be shown.
    private var showInsetBackground: Bool {
        layout == .list && listStyle == .inset
    }

    /// Background color for the view based on list style.
    private var viewBackgroundColor: Color {
        showInsetBackground ? ListBackgroundStyle.grouped.color : ListBackgroundStyle.plain.color
    }

    var body: some View {
        Group {
            if let channel {
                channelContent(channel)
            } else if let cachedHeader {
                // Show header with cached data + spinner for content area
                loadingContent(cachedHeader)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                errorView(error)
            }
        }
        .background(showInsetBackground ? viewBackgroundColor : .clear)
        .task {
            await loadChannel()
        }
        .onAppear {
            // Update Handoff activity for this specific channel
            appEnvironment?.handoffManager.updateActivity(for: .channel(channelID, source))
            loadWatchEntries()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
            loadWatchEntries()
        }
    }

    private func loadWatchEntries() {
        watchEntriesMap = appEnvironment?.dataManager.watchEntriesMap() ?? [:]
    }

    // MARK: - Computed Properties for Scroll Animation

    /// Progress from 0 (fully expanded) to 1 (fully collapsed)
    private var collapseProgress: CGFloat {
        let progress = scrollOffset / (headerHeight - collapsedHeaderHeight)
        return min(max(progress, 0), 1)
    }

    /// Current avatar size interpolated between full and collapsed
    private var currentAvatarSize: CGFloat {
        avatarSize - (avatarSize - collapsedAvatarSize) * collapseProgress
    }

    /// Opacity for expanded content (fades out as we scroll)
    private var expandedContentOpacity: CGFloat {
        1 - min(collapseProgress * 2, 1)
    }

    /// Opacity for collapsed title (fades in as we scroll)
    private var collapsedTitleOpacity: CGFloat {
        max((collapseProgress - 0.5) * 2, 0)
    }



    // MARK: - Channel Content

    @ViewBuilder
    private func channelContent(_ channel: Channel) -> some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Only hide header and tabs after user submits a search query
                        if !(isSearchActive && hasSearched) {
                            // Header with zoom/scale effect
                            header(channel)
                                .id("channelTop")

                            // Content based on instance type
                            if supportsChannelTabs {
                                // Pill-style content type switcher
                                contentTypePicker
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                            } else {
                                // Non-tab instances: show description
                                channelDescription(channel)
                            }
                        }

                        // Tab content or search results
                        // Only show search results after user has submitted a query
                        if isSearchActive && hasSearched {
                            // Spacer to push content below nav bar + search bar
                            // Since we use .ignoresSafeArea(edges: .top), we need manual spacing
                            // iOS: safe area (~59pt) + nav bar (~44pt) + search bar (~56pt) = ~130pt extra
                            // macOS: safe area + toolbar (~52pt)
                            #if os(iOS)
                            Spacer()
                                .frame(height: geometry.safeAreaInsets.top + 130)
                            #elseif os(macOS)
                            Spacer()
                                .frame(height: geometry.safeAreaInsets.top + 52)
                            #else
                            Spacer()
                                .frame(height: geometry.safeAreaInsets.top)
                            #endif
                            
                            searchResultsContent
                        } else if supportsChannelTabs {
                            tabContent
                        } else {
                            videosGrid
                        }
                    }
                }
                .onChange(of: scrollToTop) { _, shouldScroll in
                    if shouldScroll {
                        withAnimation {
                            proxy.scrollTo("channelTop", anchor: .top)
                        }
                        scrollToTop = false
                    }
                }
            }
            .onChange(of: geometry.size.width, initial: true) { _, newWidth in
                viewWidth = newWidth
            }
        }
        .background(viewBackgroundColor)
        .ignoresSafeArea(edges: .top)
        .animation(.easeInOut(duration: 0.25), value: isSearchActive)
        .modifier(ChannelScrollOffsetModifier(
            scrollOffset: $scrollOffset,
            isPlayerExpanded: appEnvironment?.navigationCoordinator.isPlayerExpanded ?? false
        ))
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Collapsed title in toolbar
                HStack(spacing: 8) {
                    if collapseProgress > 0.5 {
                        LazyImage(url: channel.thumbnailURL) { state in
                            if let image = state.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Circle()
                                    .fill(.quaternary)
                            }
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                    }

                    Text(channel.name)
                        .font(.headline)
                        .lineLimit(1)
                }
                .opacity(collapsedTitleOpacity)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showViewOptions = true
                } label: {
                    Label(String(localized: "viewOptions.title"), systemImage: "slider.horizontal.3")
                }
                .liquidGlassTransitionSource(id: "channelViewOptions", in: sheetTransition)
            }

            #if !os(tvOS)
            if #available(iOS 26, macOS 26, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            #endif

            ToolbarItem(placement: .primaryAction) {
                channelMenu
            }
        }
        .sheet(isPresented: $showViewOptions) {
            ViewOptionsSheet(
                layout: $layout,
                rowStyle: $rowStyle,
                gridColumns: $gridColumns,
                hideWatched: $hideWatched,
                maxGridColumns: gridConfig.maxColumns
            )
            .liquidGlassSheetContent(sourceID: "channelViewOptions", in: sheetTransition)
        }
        #if os(iOS)
        .toolbarBackground(collapseProgress > 0.8 ? .visible : .hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(iOS)
        .if(supportsChannelSearch) { view in
            view.searchable(
                text: $searchText,
                isPresented: $isSearchActive,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: Text("channel.search.placeholder")
            )
        }
        #elseif os(macOS)
        .if(supportsChannelSearch) { view in
            view.searchable(
                text: $searchText,
                isPresented: $isSearchActive,
                placement: .toolbar,
                prompt: Text("channel.search.placeholder")
            )
        }
        #endif
        .onSubmit(of: .search) {
            Task {
                await performSearch()
            }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty && isSearchActive {
                // User cleared the search text, reset search state
                searchResults = .empty
            }
        }
        .onChange(of: isSearchActive) { _, isActive in
            if !isActive {
                // Search was dismissed, clear results
                hasSearched = false
                searchResults = .empty
                searchText = ""
            }
        }
        .confirmationDialog(
            String(localized: "channel.unsubscribe.confirmation.title"),
            isPresented: $showingUnsubscribeConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "channel.unsubscribe.confirmation.action"), role: .destructive) {
                unsubscribe()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "channel.unsubscribe.confirmation.message"))
        }
    }

    // MARK: - Loading Content

    /// Shows cached header with a spinner below while loading full channel data.
    @ViewBuilder
    private func loadingContent(_ cached: CachedChannelData) -> some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: 0) {
                    header(name: cached.name, thumbnailURL: cached.thumbnailURL, bannerURL: cached.bannerURL)
                        .id("channelTop")

                    // Centered spinner for content area
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .onChange(of: geometry.size.width, initial: true) { _, newWidth in
                viewWidth = newWidth
            }
        }
        .background(viewBackgroundColor)
        .ignoresSafeArea(edges: .top)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Collapsed title in toolbar (using cached data)
                HStack(spacing: 8) {
                    if collapseProgress > 0.5 {
                        LazyImage(url: cached.thumbnailURL) { state in
                            if let image = state.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Circle()
                                    .fill(.ultraThinMaterial)
                            }
                        }
                        .frame(width: collapsedAvatarSize, height: collapsedAvatarSize)
                        .clipShape(Circle())

                        Text(cached.name)
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
                .opacity(collapsedTitleOpacity)
            }
        }
        .modifier(ChannelScrollOffsetModifier(
            scrollOffset: $scrollOffset,
            isPlayerExpanded: appEnvironment?.navigationCoordinator.isPlayerExpanded ?? false
        ))
    }

    // MARK: - Header

    private func header(_ channel: Channel) -> some View {
        header(name: channel.name, thumbnailURL: channel.thumbnailURL, bannerURL: channel.bannerURL)
    }

    private func header(name: String, thumbnailURL: URL?, bannerURL: URL?) -> some View {
        GeometryReader { geometry in
            // Calculate avatar vertical position
            let avatarBottomPadding: CGFloat = 20
            // Smoothly interpolate the space for channel name (40pt when visible, 0 when collapsed)
            // Name starts fading at progress 0, fully gone at 0.3
            let nameSpaceProgress = min(collapseProgress / 0.3, 1.0)
            let nameSpace: CGFloat = 40 * (1 - nameSpaceProgress)
            let avatarContentHeight: CGFloat = currentAvatarSize + nameSpace + avatarBottomPadding
            let idealAvatarY = headerHeight - avatarContentHeight
            // Minimum Y position to prevent going into nav bar
            // On iOS 18+ iPhone, the search bar is present in the navigation area (~56pt + padding)
            // We add extra height to the header, so minAvatarY just needs to clear nav bar + search
            let searchBarReservedHeight: CGFloat = needsSearchBarAdjustment ? 70 : 0
            let minAvatarY: CGFloat = 60 + searchBarReservedHeight
            let clampedAvatarY = max(idealAvatarY, minAvatarY)

            // iPad/Mac uses backgroundExtensionEffect (no zoom/scale needed)
            // iPhone uses zoom/scale + pinOffset to keep banner fixed
            let isRegularSizeClass = horizontalSizeClass != .compact
            // Pin offset: when pulling down (scrollOffset < 0), offset banner up to keep it pinned (iPhone only)
            let pinOffset = (!isRegularSizeClass && scrollOffset < 0) ? scrollOffset : 0
            // Zoom scale for banner and gradient (iPhone only)
            let zoomScale = isRegularSizeClass ? 1 : (1 + max(-scrollOffset / 400, 0))

            ZStack(alignment: .top) {
                // Banner image
                // iPad/Mac: static with backgroundExtensionEffect for Liquid Glass sidebar
                // iPhone: zoom/scale + pinOffset to keep banner fixed at top when pulling down
                bannerImage(url: bannerURL)
                    .frame(width: geometry.size.width, height: headerHeight)
                    .clipped()
                    .scaleEffect(zoomScale, anchor: .top)
                    .offset(y: pinOffset)
                    .modifier(BackgroundExtensionModifier(
                        useBackgroundExtension: isRegularSizeClass
                    ))

                // Gradient overlay for readability - matches banner scale and position
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(width: geometry.size.width, height: headerHeight * 0.7)
                .offset(y: headerHeight * 0.3)
                .scaleEffect(zoomScale, anchor: .top)
                .offset(y: pinOffset)

                // Avatar and channel name - pinned to bottom of banner
                // Smooth opacity fade based on collapse progress
                let avatarOpacity = max(0, 1.0 - collapseProgress * 1.4)
                // Channel name fades out faster than avatar (starts fading at 0, gone by 0.3)
                let nameOpacity = max(0, 1.0 - collapseProgress * 3.3)

                VStack(spacing: 8) {
                    LazyImage(url: thumbnailURL) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Text(String(name.prefix(1)))
                                        .font(.system(size: currentAvatarSize * 0.4, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(width: currentAvatarSize, height: currentAvatarSize)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.8), lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 5)

                    // Channel name with smooth fade
                    Text(name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                        .opacity(nameOpacity)
                }
                .offset(y: clampedAvatarY + pinOffset)
                .opacity(avatarOpacity)
            }
            .frame(height: headerHeight)
        }
        .frame(height: headerHeight)
    }

    // MARK: - Banner Image

    @ViewBuilder
    private func bannerImage(url bannerURL: URL?) -> some View {
        if let bannerURL {
            LazyImage(url: bannerURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [.gray.opacity(0.3), .gray.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        } else {
            // Gradient placeholder when no banner
            LinearGradient(
                colors: [.accentColor.opacity(0.6), .accentColor.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Channel Description

    /// Channel description for non-tab instances (shows full description)
    @ViewBuilder
    private func channelDescription(_ channel: Channel) -> some View {
        if let description = channel.description, !description.isEmpty {
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }

    /// Whether the current instance supports channel tabs (Invidious, Yattee Server, or Piped - not external channels)
    private var supportsChannelTabs: Bool {
        // External channels only show videos (no tabs)
        guard !isExternalChannel else { return false }
        guard let instance = instanceForSource() else {
            return false
        }
        return instance.type == .invidious || instance.type == .yatteeServer || instance.type == .piped
    }

    /// Whether the current instance supports channel search (Invidious or Yattee Server, not external channels or Piped)
    private var supportsChannelSearch: Bool {
        // External channels don't support search
        guard !isExternalChannel else { return false }
        guard let instance = instanceForSource() else { return false }
        return instance.type == .invidious || instance.type == .yatteeServer
    }

    // MARK: - Channel Menu

    /// Icon for the channel menu based on subscription/notification state
    private var channelMenuIcon: String {
        if isSubscribed {
            let notificationsEnabled = channel.map {
                appEnvironment?.dataManager.notificationsEnabled(for: $0.id.channelID) ?? false
            } ?? false
            return notificationsEnabled ? "bell.fill" : "person.fill"
        }
        return "person.badge.plus"
    }

    /// Toolbar menu for subscribe/unsubscribe and notification actions
    private var channelMenu: some View {
        Menu {
            // Subscribe/Unsubscribe button
            Button {
                toggleSubscription()
            } label: {
                Label(
                    isSubscribed
                        ? String(localized: "channel.menu.unsubscribe")
                        : String(localized: "channel.menu.subscribe"),
                    systemImage: isSubscribed ? "person.fill.xmark" : "person.badge.plus"
                )
            }

            // Notifications toggle (only visible when subscribed)
            if isSubscribed, let channel {
                let notificationsEnabled = appEnvironment?.dataManager.notificationsEnabled(for: channel.id.channelID) ?? false
                Button {
                    toggleNotifications()
                } label: {
                    Label(
                        notificationsEnabled
                            ? String(localized: "channel.menu.disableNotifications")
                            : String(localized: "channel.menu.enableNotifications"),
                        systemImage: notificationsEnabled
                            ? "bell.slash"
                            : "bell"
                    )
                }
            }
        } label: {
            Image(systemName: channelMenuIcon)
        }
    }

    // MARK: - Subscription Actions

    private func toggleSubscription() {
        if isSubscribed {
            showingUnsubscribeConfirmation = true
        } else {
            Task { await subscribe() }
        }
    }

    private func subscribe() async {
        guard let channel,
              let subscriptionService = appEnvironment?.subscriptionService,
              let dataManager = appEnvironment?.dataManager else { return }

        let author = Author(
            id: channel.id.channelID,
            name: channel.name,
            thumbnailURL: channel.thumbnailURL,
            subscriberCount: channel.subscriberCount
        )

        do {
            try await subscriptionService.subscribe(to: author, source: source)
            
            // Set default notification preference for new subscription
            let defaultNotifications = appEnvironment?.settingsManager.defaultNotificationsForNewChannels ?? false
            if defaultNotifications {
                dataManager.setNotificationsEnabled(true, for: channel.id.channelID)
            }
            
            isSubscribed = true
            refreshSubscription()
        } catch {
            appEnvironment?.toastManager.showError(
                String(localized: "channel.subscribe.error.title"),
                subtitle: error.localizedDescription
            )
        }
    }

    private func unsubscribe() {
        guard let channel else { return }

        Task {
            do {
                try await appEnvironment?.subscriptionService.unsubscribe(from: channel.id.channelID)
                isSubscribed = false
                subscription = nil
            } catch {
                appEnvironment?.toastManager.showError(
                    String(localized: "channel.unsubscribe.error.title"),
                    subtitle: error.localizedDescription
                )
            }
        }
    }

    private func toggleNotifications() {
        guard let channel else { return }
        let currentEnabled = appEnvironment?.dataManager.notificationsEnabled(for: channel.id.channelID) ?? false

        if currentEnabled {
            appEnvironment?.dataManager.setNotificationsEnabled(false, for: channel.id.channelID)
        } else {
            Task {
                guard let appEnvironment, await appEnvironment.ensureNotificationsEnabled() else { return }
                appEnvironment.dataManager.setNotificationsEnabled(true, for: channel.id.channelID)
            }
        }
    }

    // MARK: - Content Type Picker

    /// Pill-style segmented picker for switching between content types
    private var contentTypePicker: some View {
        Picker("", selection: $selectedTab) {
            Text(ChannelTab.about.title).tag(ChannelTab.about)
            Text(ChannelTab.videos.title).tag(ChannelTab.videos)
            Text(ChannelTab.shorts.title).tag(ChannelTab.shorts)
            Text(ChannelTab.streams.title).tag(ChannelTab.streams)
            Text(ChannelTab.playlists.title).tag(ChannelTab.playlists)
        }
        .pickerStyle(.segmented)
        .onChange(of: selectedTab) { oldTab, newTab in
            if oldTab != newTab {
                scrollToTop = true
                Task {
                    await loadTabContentIfNeeded(newTab)
                }
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .about:
            aboutContent
        case .videos:
            videosGrid
        case .playlists:
            playlistsGrid
        case .shorts:
            shortsGrid
        case .streams:
            streamsGrid
        }
    }

    // MARK: - About Content

    @ViewBuilder
    private var aboutContent: some View {
        if let channel {
            let hasSubscriberCount = channel.subscriberCount != nil
            let hasDescription = channel.description?.isEmpty == false

            if hasSubscriberCount || hasDescription {
                let content = VStack(alignment: .leading, spacing: 12) {
                    // Subscriber count (count is bold, "subscribers" is regular)
                    if let subscriberCount = channel.subscriberCount {
                        Text(CountFormatter.compact(subscriberCount))
                            .fontWeight(.bold)
                        + Text(verbatim: " ")
                        + Text(String(localized: "channel.subscribers"))
                    }

                    // Description
                    if let description = channel.description, !description.isEmpty {
                        Text(DescriptionText.attributed(description, linkColor: accentColor))
                            .font(.subheadline)
                            .tint(accentColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if showInsetBackground {
                    content
                        .background(ListBackgroundStyle.card.color)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16)
                } else {
                    content
                }
            } else {
                ContentUnavailableView {
                    Label(String(localized: "channel.noDescription"), systemImage: "text.alignleft")
                }
                .padding(.vertical, 40)
            }
        }
    }

    // MARK: - Videos Grid

    /// Queue source for continuation loading
    private var videosQueueSource: QueueSource {
        .channel(channelID: channelID, source: source, continuation: videosContinuation)
    }

    @ViewBuilder
    private var videosGrid: some View {
        switch layout {
        case .list:
            videosListContent
        case .grid:
            videosGridContent
        }
    }

    @ViewBuilder
    private var videosListContent: some View {
        if videosLoaded && filteredVideos.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "channel.noVideos"), systemImage: "play.rectangle")
            }
            .padding(.vertical, 40)
        } else if !filteredVideos.isEmpty {
            VideoListContent(listStyle: listStyle) {
                ForEach(Array(filteredVideos.enumerated()), id: \.element.id) { index, video in
                    VideoListRow(
                        isLast: index == filteredVideos.count - 1,
                        rowStyle: rowStyle,
                        listStyle: listStyle
                    ) {
                        VideoRowView(video: video, style: rowStyle)
                            .tappableVideo(
                                video,
                                queueSource: videosQueueSource,
                                sourceLabel: channel?.name,
                                videoList: filteredVideos,
                                videoIndex: index,
                                loadMoreVideos: loadMoreVideosCallback
                            )
                    }
                    #if !os(tvOS)
                    .videoSwipeActions(video: video)
                    #endif
                }

                // External channels use manual load more button
                if isExternalChannel {
                    externalLoadMoreButton
                } else {
                    LoadMoreTrigger(
                        isLoading: isLoadingMore && selectedTab == .videos,
                        hasMore: videosContinuation != nil
                    ) {
                        Task { await loadMoreVideos() }
                    }
                }
            }
        }
    }

    /// Manual load more button for external channels
    private var externalLoadMoreButton: some View {
        Group {
            if videosContinuation != nil {
                Button {
                    Task { await loadMoreVideos() }
                } label: {
                    HStack {
                        if isLoadingMore {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text(isLoadingMore
                            ? String(localized: "externalChannel.loadingMore")
                            : String(localized: "externalChannel.loadMore"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingMore)
                .padding()
            }
        }
    }

    @ViewBuilder
    private var videosGridContent: some View {
        VideoGridContent(columns: gridConfig.effectiveColumns) {
            ForEach(Array(filteredVideos.enumerated()), id: \.element.id) { index, video in
                VideoCardView(video: video, isCompact: gridConfig.isCompactCards)
                    .tappableVideo(
                        video,
                        queueSource: videosQueueSource,
                        sourceLabel: channel?.name,
                        videoList: filteredVideos,
                        videoIndex: index,
                        loadMoreVideos: loadMoreVideosCallback
                    )

                // Load more trigger (automatic for regular channels)
                if !isExternalChannel && video.id == filteredVideos.last?.id && videosContinuation != nil && !isLoadingMore {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task {
                                await loadMoreVideos()
                            }
                        }
                }
            }
        }

        if videosLoaded && filteredVideos.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "channel.noVideos"), systemImage: "play.rectangle")
            }
            .padding(.vertical, 40)
        }

        // External channels use manual load more button
        if isExternalChannel {
            externalLoadMoreButton
        } else if isLoadingMore && selectedTab == .videos {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
        }
    }

    // MARK: - Playlists Grid

    @ViewBuilder
    private var playlistsGrid: some View {
        switch layout {
        case .list:
            playlistsListContent
        case .grid:
            playlistsGridContent
        }
    }

    @ViewBuilder
    private var playlistsListContent: some View {
        // Loading state
        if !playlistsLoaded && playlists.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
                .onAppear {
                    Task { await loadPlaylists() }
                }
        }

        if playlistsLoaded && playlists.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "channel.noPlaylists"), systemImage: "list.bullet.rectangle")
            }
            .padding(.vertical, 40)
        } else if !playlists.isEmpty {
            VideoListContent(listStyle: listStyle) {
                ForEach(Array(playlists.enumerated()), id: \.element.id) { index, playlist in
                    VideoListRow(
                        isLast: index == playlists.count - 1,
                        rowStyle: rowStyle,
                        listStyle: listStyle
                    ) {
                        ChannelPlaylistRow(playlist: playlist, style: rowStyle)
                    }
                }

                LoadMoreTrigger(
                    isLoading: isLoadingMore && selectedTab == .playlists,
                    hasMore: playlistsContinuation != nil
                ) {
                    Task { await loadMorePlaylists() }
                }
            }
        }
    }

    @ViewBuilder
    private var playlistsGridContent: some View {
        if !playlistsLoaded && playlists.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
                .onAppear {
                    Task {
                        await loadPlaylists()
                    }
                }
        }

        VideoGridContent(columns: gridConfig.effectiveColumns) {
            ForEach(playlists) { playlist in
                NavigationLink(value: NavigationDestination.playlist(.remote(playlist.id, instance: nil, title: playlist.title))) {
                    PlaylistCardView(playlist: playlist, isCompact: gridConfig.isCompactCards)
                        .contentShape(Rectangle())
                }
                .zoomTransitionSource(id: playlist.id)
                .buttonStyle(.plain)

                // Load more trigger
                if playlist.id == playlists.last?.id && playlistsContinuation != nil && !isLoadingMore {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task {
                                await loadMorePlaylists()
                            }
                        }
                }
            }
        }

        if playlistsLoaded && playlists.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "channel.noPlaylists"), systemImage: "list.bullet.rectangle")
            }
            .padding(.vertical, 40)
        }

        if isLoadingMore && selectedTab == .playlists {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
        }
    }

    // MARK: - Shorts Grid

    private var shortsQueueSource: QueueSource {
        .channel(channelID: channelID, source: source, continuation: shortsContinuation)
    }

    @ViewBuilder
    private var shortsGrid: some View {
        switch layout {
        case .list:
            shortsListContent
        case .grid:
            shortsGridContent
        }
    }

    @ViewBuilder
    private var shortsListContent: some View {
        // Loading state
        if !shortsLoaded && filteredShorts.isEmpty && shorts.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
                .onAppear {
                    Task { await loadShorts() }
                }
        }

        if shortsLoaded && filteredShorts.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "channel.noShorts"), systemImage: "bolt")
            }
            .padding(.vertical, 40)
        } else if !filteredShorts.isEmpty {
            VideoListContent(listStyle: listStyle) {
                ForEach(Array(filteredShorts.enumerated()), id: \.element.id) { index, video in
                    VideoListRow(
                        isLast: index == filteredShorts.count - 1,
                        rowStyle: rowStyle,
                        listStyle: listStyle
                    ) {
                        VideoRowView(video: video, style: rowStyle)
                            .tappableVideo(
                                video,
                                queueSource: shortsQueueSource,
                                sourceLabel: channel?.name,
                                videoList: filteredShorts,
                                videoIndex: index,
                                loadMoreVideos: loadMoreShortsCallback
                            )
                    }
                    #if !os(tvOS)
                    .videoSwipeActions(video: video)
                    #endif
                }

                LoadMoreTrigger(
                    isLoading: isLoadingMore && selectedTab == .shorts,
                    hasMore: shortsContinuation != nil
                ) {
                    Task { await loadMoreShorts() }
                }
            }
        }
    }

    @ViewBuilder
    private var shortsGridContent: some View {
        if !shortsLoaded && filteredShorts.isEmpty && shorts.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
                .onAppear {
                    Task {
                        await loadShorts()
                    }
                }
        }

        VideoGridContent(columns: gridConfig.effectiveColumns) {
            ForEach(Array(filteredShorts.enumerated()), id: \.element.id) { index, video in
                VideoCardView(video: video, isCompact: gridConfig.isCompactCards)
                    .tappableVideo(
                        video,
                        queueSource: shortsQueueSource,
                        sourceLabel: channel?.name,
                        videoList: filteredShorts,
                        videoIndex: index,
                        loadMoreVideos: loadMoreShortsCallback
                    )

                // Load more trigger
                if video.id == filteredShorts.last?.id && shortsContinuation != nil && !isLoadingMore {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task {
                                await loadMoreShorts()
                            }
                        }
                }
            }
        }

        if shortsLoaded && filteredShorts.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "channel.noShorts"), systemImage: "bolt")
            }
            .padding(.vertical, 40)
        }

        if isLoadingMore && selectedTab == .shorts {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
        }
    }

    // MARK: - Streams Grid

    private var streamsQueueSource: QueueSource {
        .channel(channelID: channelID, source: source, continuation: streamsContinuation)
    }

    @ViewBuilder
    private var streamsGrid: some View {
        switch layout {
        case .list:
            streamsListContent
        case .grid:
            streamsGridContent
        }
    }

    @ViewBuilder
    private var streamsListContent: some View {
        // Loading state
        if !streamsLoaded && filteredStreams.isEmpty && streams.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
                .onAppear {
                    Task { await loadStreams() }
                }
        }

        if streamsLoaded && filteredStreams.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "channel.noStreams"), systemImage: "video")
            }
            .padding(.vertical, 40)
        } else if !filteredStreams.isEmpty {
            VideoListContent(listStyle: listStyle) {
                ForEach(Array(filteredStreams.enumerated()), id: \.element.id) { index, video in
                    VideoListRow(
                        isLast: index == filteredStreams.count - 1,
                        rowStyle: rowStyle,
                        listStyle: listStyle
                    ) {
                        VideoRowView(video: video, style: rowStyle)
                            .tappableVideo(
                                video,
                                queueSource: streamsQueueSource,
                                sourceLabel: channel?.name,
                                videoList: filteredStreams,
                                videoIndex: index,
                                loadMoreVideos: loadMoreStreamsCallback
                            )
                    }
                    #if !os(tvOS)
                    .videoSwipeActions(video: video)
                    #endif
                }

                LoadMoreTrigger(
                    isLoading: isLoadingMore && selectedTab == .streams,
                    hasMore: streamsContinuation != nil
                ) {
                    Task { await loadMoreStreams() }
                }
            }
        }
    }

    @ViewBuilder
    private var streamsGridContent: some View {
        if !streamsLoaded && filteredStreams.isEmpty && streams.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
                .onAppear {
                    Task {
                        await loadStreams()
                    }
                }
        }

        VideoGridContent(columns: gridConfig.effectiveColumns) {
            ForEach(Array(filteredStreams.enumerated()), id: \.element.id) { index, video in
                VideoCardView(video: video, isCompact: gridConfig.isCompactCards)
                    .tappableVideo(
                        video,
                        queueSource: streamsQueueSource,
                        sourceLabel: channel?.name,
                        videoList: filteredStreams,
                        videoIndex: index,
                        loadMoreVideos: loadMoreStreamsCallback
                    )

                // Load more trigger
                if video.id == filteredStreams.last?.id && streamsContinuation != nil && !isLoadingMore {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task {
                                await loadMoreStreams()
                            }
                        }
                }
            }
        }

        if streamsLoaded && filteredStreams.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "channel.noStreams"), systemImage: "video")
            }
            .padding(.vertical, 40)
        }

        if isLoadingMore && selectedTab == .streams {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
        }
    }

    // MARK: - Search Results

    /// Queue source for search results (no continuation since channel search uses pages)
    private var searchQueueSource: QueueSource {
        .search(query: searchText, continuation: nil)
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        if isSearchLoading && searchResults.items.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if searchResults.items.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .padding(.vertical, 40)
        } else {
            switch layout {
            case .list:
                searchResultsListContent
            case .grid:
                searchResultsGridContent
            }
        }
    }

    @ViewBuilder
    private var searchResultsListContent: some View {
        VideoListContent(listStyle: listStyle) {
            ForEach(Array(searchResults.items.enumerated()), id: \.element.id) { index, item in
                VideoListRow(
                    isLast: index == searchResults.items.count - 1,
                    rowStyle: rowStyle,
                    listStyle: listStyle
                ) {
                    switch item {
                    case .video(let video):
                        VideoRowView(video: video, style: rowStyle)
                            .tappableVideo(
                                video,
                                queueSource: searchQueueSource,
                                sourceLabel: channel?.name,
                                videoList: searchResultVideos,
                                videoIndex: searchResultVideos.firstIndex(where: { $0.id == video.id }) ?? 0,
                                loadMoreVideos: nil
                            )
                            #if !os(tvOS)
                            .videoSwipeActions(video: video)
                            #endif

                    case .playlist(let playlist):
                        ChannelPlaylistRow(playlist: playlist, style: rowStyle)
                    }
                }
            }

            LoadMoreTrigger(
                isLoading: isSearchLoading,
                hasMore: searchResults.nextPage != nil
            ) {
                Task { await loadMoreSearchResults() }
            }
        }
    }

    @ViewBuilder
    private var searchResultsGridContent: some View {
        VideoGridContent(columns: gridConfig.effectiveColumns) {
            ForEach(searchResults.items) { item in
                switch item {
                case .video(let video):
                    VideoCardView(video: video, isCompact: gridConfig.isCompactCards)
                        .tappableVideo(
                            video,
                            queueSource: searchQueueSource,
                            sourceLabel: channel?.name,
                            videoList: searchResultVideos,
                            videoIndex: searchResultVideos.firstIndex(where: { $0.id == video.id }) ?? 0,
                            loadMoreVideos: nil
                        )

                case .playlist(let playlist):
                NavigationLink(value: NavigationDestination.playlist(.remote(playlist.id, instance: nil, title: playlist.title))) {
                        PlaylistCardView(playlist: playlist, isCompact: gridConfig.isCompactCards)
                            .contentShape(Rectangle())
                    }
                    .zoomTransitionSource(id: playlist.id)
                    .buttonStyle(.plain)
                }

                // Load more trigger
                if item.id == searchResults.items.last?.id && searchResults.nextPage != nil && !isSearchLoading {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task {
                                await loadMoreSearchResults()
                            }
                        }
                }
            }
        }

        if isSearchLoading && !searchResults.items.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
        }
    }

    /// Extracts just the videos from search results for queue navigation
    private var searchResultVideos: [Video] {
        searchResults.items.compactMap { item in
            if case .video(let video) = item {
                return video
            }
            return nil
        }
    }

    // MARK: - Search Loading

    private func performSearch() async {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let appEnvironment,
              let instance = instanceForSource() else {
            return
        }

        isSearchLoading = true
        hasSearched = true

        do {
            let results = try await appEnvironment.contentService.channelSearch(
                id: channelID,
                query: searchText,
                instance: instance,
                page: 1
            )
            // Deduplicate items (API may return duplicates)
            var seenIDs = Set<String>()
            let uniqueItems = results.items.filter { seenIDs.insert($0.id).inserted }
            searchResults = ChannelSearchPage(items: uniqueItems, nextPage: results.nextPage)
        } catch {
            // On error, show empty results
            searchResults = .empty
        }

        isSearchLoading = false
    }

    private func loadMoreSearchResults() async {
        guard let nextPage = searchResults.nextPage,
              let appEnvironment,
              let instance = instanceForSource(),
              !isSearchLoading else {
            return
        }

        isSearchLoading = true

        do {
            let moreResults = try await appEnvironment.contentService.channelSearch(
                id: channelID,
                query: searchText,
                instance: instance,
                page: nextPage
            )

            // Append new items, avoiding duplicates
            let existingIDs = Set(searchResults.items.map(\.id))
            let newItems = moreResults.items.filter { !existingIDs.contains($0.id) }

            searchResults = ChannelSearchPage(
                items: searchResults.items + newItems,
                nextPage: newItems.isEmpty ? nil : moreResults.nextPage
            )
        } catch {
            // On error, stop loading more
        }

        isSearchLoading = false
    }

    private func clearSearch() {
        isSearchActive = false
        hasSearched = false
        searchResults = .empty
        searchText = ""
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        ContentUnavailableView {
            Label(String(localized: "common.error"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button(String(localized: "common.retry")) {
                Task {
                    await loadChannel()
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatSubscribers(_ count: Int) -> String {
        let formatted = CountFormatter.compact(count)
        return String(localized: "channel.subscriberCount \(formatted)")
    }

    /// Returns the appropriate instance for the channel's content source
    private func instanceForSource() -> Instance? {
        appEnvironment?.instancesManager.instance(for: source)
    }

    // MARK: - Data Loading

    private func loadChannel() async {
        if isExternalChannel {
            await loadExternalChannel()
        } else {
            await loadRegularChannel()
        }
    }

    private func loadRegularChannel() async {
        guard let appEnvironment,
              let instance = instanceForSource() else {
            errorMessage = "No instances configured"
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        // Load subscription state
        subscription = appEnvironment.dataManager.subscription(for: channelID)
        isSubscribed = subscription != nil

        // Load cached header data for immediate display
        cachedHeader = CachedChannelData.load(for: channelID, using: appEnvironment.dataManager)

        // Fetch channel and videos independently to handle partial failures gracefully
        async let channelTask: Result<Channel, Error> = await {
            do {
                return .success(try await appEnvironment.contentService.channel(id: channelID, instance: instance))
            } catch {
                return .failure(error)
            }
        }()
        async let videosTask: Result<ChannelVideosPage, Error> = await {
            do {
                return .success(try await appEnvironment.contentService.channelVideos(id: channelID, instance: instance, continuation: nil))
            } catch {
                return .failure(error)
            }
        }()

        let (channelResult, videosResult) = await (channelTask, videosTask)

        await MainActor.run {
            var channelAPIFailed = false
            var videosAPIFailed = false

            // Handle channel result
            switch channelResult {
            case .success(let loadedChannel):
                channel = loadedChannel

                // Update subscription metadata if subscribed
                appEnvironment.dataManager.updateSubscription(for: channelID, with: loadedChannel)

                // Save to recent channels (unless incognito mode is enabled or recent channels disabled)
                if appEnvironment.settingsManager.incognitoModeEnabled != true,
                   appEnvironment.settingsManager.saveRecentChannels {
                    appEnvironment.dataManager.addRecentChannel(loadedChannel)
                }

            case .failure(let error):
                channelAPIFailed = true
                // Channel API failed - build a Channel from cachedHeader so the view can display it
                if let cached = cachedHeader {
                    channel = Channel(
                        id: ChannelID(source: source, channelID: channelID),
                        name: cached.name,
                        description: nil,
                        subscriberCount: cached.subscriberCount,
                        thumbnailURL: cached.thumbnailURL,
                        bannerURL: cached.bannerURL
                    )
                }
                LoggingService.shared.error("[ChannelView] Channel API failed", category: .api, details: error.localizedDescription)
            }

            // Handle videos result
            switch videosResult {
            case .success(let videosPage):
                videos = videosPage.videos
                videosContinuation = videosPage.continuation
                videosLoaded = true

            case .failure(let error):
                videosAPIFailed = true
                LoggingService.shared.error("[ChannelView] Videos API failed", category: .api, details: error.localizedDescription)
            }

            // Only show error if both APIs failed and we have no cached data
            if channelAPIFailed && videosAPIFailed && channel == nil {
                errorMessage = String(localized: "channelView.loadError")
            }

            isLoading = false
        }
    }

    private func loadExternalChannel() async {
        guard let appEnvironment,
              let url = channelURL else {
            errorMessage = "Invalid channel URL"
            isLoading = false
            return
        }

        guard let instance = appEnvironment.instancesManager.yatteeServerInstance else {
            errorMessage = String(localized: "externalChannel.noYatteeServer")
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let (fetchedChannel, fetchedVideos, fetchedContinuation) = try await appEnvironment.contentService.extractChannel(
                url: url,
                page: 1,
                instance: instance
            )

            await MainActor.run {
                channel = fetchedChannel
                videos = fetchedVideos
                videosContinuation = fetchedContinuation
                externalCurrentPage = 1
                videosLoaded = true
                isLoading = false

                // Check subscription status using extracted channel ID
                subscription = appEnvironment.dataManager.subscription(for: fetchedChannel.id.channelID)
                isSubscribed = subscription != nil
            }
        } catch let error as APIError {
            await MainActor.run {
                handleExternalChannelError(error)
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func handleExternalChannelError(_ error: APIError) {
        switch error {
        case .httpError(let statusCode, let message):
            if statusCode == 422 {
                errorMessage = message ?? "This site doesn't support channel extraction."
            } else if statusCode == 400 {
                errorMessage = message ?? "Invalid channel URL."
            } else {
                errorMessage = message ?? "Server error (\(statusCode))."
            }
        default:
            errorMessage = error.localizedDescription
        }
    }

    private func refreshSubscription() {
        // Use loaded channel's ID if available (important for external channels
        // where navigation channelID is the URL, not the actual channel ID)
        let effectiveChannelID = channel?.id.channelID ?? channelID
        subscription = appEnvironment?.dataManager.subscription(for: effectiveChannelID)
        isSubscribed = subscription != nil
    }

    private func loadMoreVideos() async {
        if isExternalChannel {
            await loadMoreExternalVideos()
        } else {
            await loadMoreRegularVideos()
        }
    }

    private func loadMoreRegularVideos() async {
        guard let appEnvironment,
              let instance = instanceForSource(),
              let continuation = videosContinuation,
              !isLoadingMore else {
            return
        }

        isLoadingMore = true

        do {
            let result = try await appEnvironment.contentService.channelVideos(
                id: channelID,
                instance: instance,
                continuation: continuation
            )

            await MainActor.run {
                // Filter out duplicates before appending
                let existingIDs = Set(videos.map(\.id))
                let newVideos = result.videos.filter { !existingIDs.contains($0.id) }

                videos.append(contentsOf: newVideos)
                // Stop pagination if all returned videos are duplicates
                videosContinuation = newVideos.isEmpty ? nil : result.continuation
                isLoadingMore = false
            }
        } catch {
            await MainActor.run {
                isLoadingMore = false
            }
        }
    }

    private func loadMoreExternalVideos() async {
        guard let appEnvironment,
              let url = channelURL,
              let instance = appEnvironment.instancesManager.yatteeServerInstance,
              videosContinuation != nil,
              !isLoadingMore else {
            return
        }

        isLoadingMore = true

        do {
            let nextPage = externalCurrentPage + 1
            let (_, fetchedVideos, fetchedContinuation) = try await appEnvironment.contentService.extractChannel(
                url: url,
                page: nextPage,
                instance: instance
            )

            await MainActor.run {
                videos.append(contentsOf: fetchedVideos)
                videosContinuation = fetchedContinuation
                externalCurrentPage = nextPage
                isLoadingMore = false
            }
        } catch {
            await MainActor.run {
                isLoadingMore = false
            }
        }
    }
    
    /// Callback for loading more videos via continuation (used by VideoInfoView navigation)
    @Sendable
    private func loadMoreVideosCallback() async throws -> ([Video], String?) {
        guard let appEnvironment,
              let instance = instanceForSource(),
              let continuation = videosContinuation else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No continuation available"])
        }
        
        let result = try await appEnvironment.contentService.channelVideos(
            id: channelID,
            instance: instance,
            continuation: continuation
        )
        
        return (result.videos, result.continuation)
    }
    
    /// Callback for loading more shorts via continuation
    @Sendable
    private func loadMoreShortsCallback() async throws -> ([Video], String?) {
        guard let appEnvironment,
              let instance = instanceForSource(),
              let continuation = shortsContinuation else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No continuation available"])
        }
        
        let result = try await appEnvironment.contentService.channelShorts(
            id: channelID,
            instance: instance,
            continuation: continuation
        )
        
        return (result.videos, result.continuation)
    }
    
    /// Callback for loading more streams via continuation
    @Sendable
    private func loadMoreStreamsCallback() async throws -> ([Video], String?) {
        guard let appEnvironment,
              let instance = instanceForSource(),
              let continuation = streamsContinuation else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No continuation available"])
        }
        
        let result = try await appEnvironment.contentService.channelStreams(
            id: channelID,
            instance: instance,
            continuation: continuation
        )
        
        return (result.videos, result.continuation)
    }

    // MARK: - Tab Loading

    private func loadTabContentIfNeeded(_ tab: ChannelTab) async {
        switch tab {
        case .about:
            // No loading needed - description is already available
            break
        case .videos:
            // Already loaded on initial load
            break
        case .playlists:
            if !playlistsLoaded {
                await loadPlaylists()
            }
        case .shorts:
            if !shortsLoaded {
                await loadShorts()
            }
        case .streams:
            if !streamsLoaded {
                await loadStreams()
            }
        }
    }

    // MARK: - Playlists Loading

    private func loadPlaylists() async {
        guard let appEnvironment,
              let instance = instanceForSource() else {
            return
        }

        do {
            let result = try await appEnvironment.contentService.channelPlaylists(
                id: channelID,
                instance: instance,
                continuation: nil
            )

            await MainActor.run {
                playlists = result.playlists
                playlistsContinuation = result.continuation
                playlistsLoaded = true
            }
        } catch {
            await MainActor.run {
                playlistsLoaded = true
            }
        }
    }

    private func loadMorePlaylists() async {
        guard let appEnvironment,
              let instance = instanceForSource(),
              let continuation = playlistsContinuation,
              !isLoadingMore else {
            return
        }

        isLoadingMore = true

        do {
            let result = try await appEnvironment.contentService.channelPlaylists(
                id: channelID,
                instance: instance,
                continuation: continuation
            )

            await MainActor.run {
                playlists.append(contentsOf: result.playlists)
                playlistsContinuation = result.continuation
                isLoadingMore = false
            }
        } catch {
            await MainActor.run {
                isLoadingMore = false
            }
        }
    }

    // MARK: - Shorts Loading

    private func loadShorts() async {
        guard let appEnvironment,
              let instance = instanceForSource() else {
            return
        }

        do {
            let result = try await appEnvironment.contentService.channelShorts(
                id: channelID,
                instance: instance,
                continuation: nil
            )

            await MainActor.run {
                shorts = result.videos
                shortsContinuation = result.continuation
                shortsLoaded = true
            }
        } catch {
            await MainActor.run {
                shortsLoaded = true
            }
        }
    }

    private func loadMoreShorts() async {
        guard let appEnvironment,
              let instance = instanceForSource(),
              let continuation = shortsContinuation,
              !isLoadingMore else {
            return
        }

        isLoadingMore = true

        do {
            let result = try await appEnvironment.contentService.channelShorts(
                id: channelID,
                instance: instance,
                continuation: continuation
            )

            await MainActor.run {
                // Filter out duplicates before appending
                let existingIDs = Set(shorts.map(\.id))
                let newShorts = result.videos.filter { !existingIDs.contains($0.id) }
                shorts.append(contentsOf: newShorts)
                // Stop pagination if all returned videos are duplicates
                shortsContinuation = newShorts.isEmpty ? nil : result.continuation
                isLoadingMore = false
            }
        } catch {
            await MainActor.run {
                isLoadingMore = false
            }
        }
    }

    // MARK: - Streams Loading

    private func loadStreams() async {
        guard let appEnvironment,
              let instance = instanceForSource() else {
            return
        }

        do {
            let result = try await appEnvironment.contentService.channelStreams(
                id: channelID,
                instance: instance,
                continuation: nil
            )

            await MainActor.run {
                streams = result.videos
                streamsContinuation = result.continuation
                streamsLoaded = true
            }
        } catch {
            await MainActor.run {
                streamsLoaded = true
            }
        }
    }

    private func loadMoreStreams() async {
        guard let appEnvironment,
              let instance = instanceForSource(),
              let continuation = streamsContinuation,
              !isLoadingMore else {
            return
        }

        isLoadingMore = true

        do {
            let result = try await appEnvironment.contentService.channelStreams(
                id: channelID,
                instance: instance,
                continuation: continuation
            )

            await MainActor.run {
                // Filter out duplicates before appending
                let existingIDs = Set(streams.map(\.id))
                let newStreams = result.videos.filter { !existingIDs.contains($0.id) }
                streams.append(contentsOf: newStreams)
                // Stop pagination if all returned videos are duplicates
                streamsContinuation = newStreams.isEmpty ? nil : result.continuation
                isLoadingMore = false
            }
        } catch {
            await MainActor.run {
                isLoadingMore = false
            }
        }
    }
}

// MARK: - Scroll Offset Tracking Modifier

/// Tracks scroll offset for header zoom/scale effect
private struct ChannelScrollOffsetModifier: ViewModifier {
    @Binding var scrollOffset: CGFloat
    var isPlayerExpanded: Bool

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                // Skip updates when player is expanded to avoid multiple updates per frame
                guard !isPlayerExpanded else { return }

                if scrollOffset != newValue {
                    scrollOffset = newValue
                }
            }
    }
}

// MARK: - Background Extension Modifier

/// Applies backgroundExtensionEffect on iOS 26+ for Liquid Glass sidebar (iPad/Mac only)
private struct BackgroundExtensionModifier: ViewModifier {
    let useBackgroundExtension: Bool
    
    func body(content: Content) -> some View {
        if useBackgroundExtension {
            if #available(iOS 26, macOS 26, tvOS 26, *) {
                content.backgroundExtensionEffect()
            } else {
                content
            }
        } else {
            content
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ChannelView(channelID: "UCxxxxxx", source: .global(provider: ContentSource.youtubeProvider))
    }
    .appEnvironment(.preview)
}
