//
//  InstanceBrowseView.swift
//  Yattee
//
//  Displays content (Popular/Trending) for a specific backend instance.
//

import SwiftUI

struct InstanceBrowseView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let instance: Instance
    let initialTab: BrowseTab?

    @Namespace private var sheetTransition
    @State private var selectedTab: BrowseTab = .popular
    @State private var popularVideos: [Video] = []
    @State private var trendingVideos: [Video] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Search state (managed by SearchViewModel)
    @State private var searchText = ""
    @State private var searchViewModel: SearchViewModel?
    @State private var showFilterSheet = false

    // Feed state (for Invidious/Piped login)
    @State private var feedVideos: [Video] = []
    @State private var feedSubscriptions: [Channel] = []
    
    // Playlists state (for Invidious login)
    @State private var userPlaylists: [Playlist] = []
    @State private var selectedFeedChannelID: String?
    @State private var isLoggedIn = false
    @State private var feedPage = 1
    @State private var hasMoreFeedResults = true
    @State private var isLoadingMoreFeed = false
    @State private var contentLoadTask: Task<Void, Never>?
    @State private var feedLoadedVideoCount = 0  // Track count when last load was triggered
    
    // View options (persisted per instance)
    @AppStorage var layout: VideoListLayout
    @AppStorage var rowStyle: VideoRowStyle
    @AppStorage var gridColumnCount: Int
    @AppStorage var hideWatched: Bool
    
    // View options UI state
    @State private var showViewOptions = false
    @State private var viewWidth: CGFloat = 0
    @State private var watchEntriesMap: [String: WatchEntry] = [:]
    @State private var hasInitializedTab = false
    
    init(instance: Instance, initialTab: BrowseTab? = nil) {
        self.instance = instance
        self.initialTab = initialTab

        // Initialize AppStorage with instance-scoped keys
        _layout = AppStorage(wrappedValue: .list, "instanceBrowse.\(instance.id).layout")
        _rowStyle = AppStorage(wrappedValue: .regular, "instanceBrowse.\(instance.id).rowStyle")
        _gridColumnCount = AppStorage(wrappedValue: 2, "instanceBrowse.\(instance.id).gridColumns")
        _hideWatched = AppStorage(wrappedValue: false, "instanceBrowse.\(instance.id).hideWatched")
    }

    /// List style from centralized settings.
    private var listStyle: VideoListStyle {
        appEnvironment?.settingsManager.listStyle ?? .inset
    }

    /// The first enabled Yattee Server instance (for avatar URLs).
    private var yatteeServer: Instance? {
        appEnvironment?.instancesManager.enabledYatteeServerInstances.first
    }
    private var yatteeServerURL: URL? { yatteeServer?.url }

    /// Auth header for Yattee Server instances (when browsing a Yattee Server directly)
    private var yatteeServerAuthHeader: String? {
        guard instance.type == .yatteeServer else { return nil }
        return appEnvironment?.yatteeServerCredentialsManager.basicAuthHeader(for: instance)
    }

    /// Auth header for avatar loading (uses Yattee Server for YouTube channel avatars)
    private var avatarAuthHeader: String? {
        guard let server = yatteeServer else { return nil }
        return appEnvironment?.yatteeServerCredentialsManager.basicAuthHeader(for: server)
    }

    enum BrowseTab: String, CaseIterable, Identifiable {
        case popular
        case trending
        case feed
        case playlists

        var id: String { rawValue }

        var title: String {
            switch self {
            case .popular: return String(localized: "popular.title")
            case .trending: return String(localized: "trending.title")
            case .feed: return String(localized: "feed.title")
            case .playlists: return String(localized: "playlists.title")
            }
        }

        var systemImage: String {
            switch self {
            case .popular: return "flame"
            case .trending: return "chart.line.uptrend.xyaxis"
            case .feed: return "person.crop.rectangle.stack"
            case .playlists: return "play.square.stack"
            }
        }
    }

    var body: some View {
        let backgroundStyle: ListBackgroundStyle = listStyle == .inset ? .grouped : .plain
        GeometryReader { geometry in
            backgroundStyle.color
                .ignoresSafeArea()
                .overlay(
                    ScrollView {
                        VStack(spacing: 0) {
                            // Tab picker (hidden during search)
                            if !isInSearchMode {
                                Picker("", selection: $selectedTab) {
                                    ForEach(availableTabs) { tab in
                                        Label(tab.title, systemImage: tab.systemImage)
                                            .tag(tab)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .padding()
                            }

                            // Feed channel filter strip (hidden during search)
                            if selectedTab == .feed && !feedSubscriptions.isEmpty && !isInSearchMode {
                                feedChannelFilterStrip
                            }

                            // Search filter strip (shown persistently after search submitted)
                            if isInSearchMode && (searchViewModel?.hasSearched ?? false) && instance.supportsSearchFilters {
                                searchFiltersStrip
                            }

                            // Content
                            Group {
                                if isInSearchMode, let vm = searchViewModel {
                                    // Search mode content
                                    if !vm.hasSearched {
                                        // Typing but not yet submitted - show suggestions or hint
                                        if vm.suggestions.isEmpty {
                                            searchHintView
                                        } else {
                                            suggestionsView
                                        }
                                    } else if vm.isSearching && !vm.hasResults {
                                        ProgressView()
                                            .frame(maxWidth: .infinity, minHeight: 200)
                                    } else if let error = vm.errorMessage, !vm.hasResults {
                                        searchErrorView(error)
                                    } else if vm.hasResults {
                                        searchResultsContent
                                    } else {
                                        searchEmptyView
                                    }
                                } else if selectedTab == .playlists {
                                    // Playlists tab content
                                    if isLoading && userPlaylists.isEmpty {
                                        ProgressView()
                                            .frame(maxWidth: .infinity, minHeight: 200)
                                    } else if let error = errorMessage, userPlaylists.isEmpty {
                                        errorView(error)
                                    } else if !userPlaylists.isEmpty {
                                        switch layout {
                                        case .list:
                                            playlistsListContent
                                        case .grid:
                                            playlistsGridContent
                                        }
                                    } else {
                                        playlistsEmptyView
                                    }
                                } else if isLoading && currentVideos.isEmpty {
                                    ProgressView()
                                        .frame(maxWidth: .infinity, minHeight: 200)
                                } else if let error = errorMessage, currentVideos.isEmpty {
                                    errorView(error)
                                } else if !currentVideos.isEmpty {
                                    // Conditional layout based on user preference
                                    switch layout {
                                    case .list:
                                        listContent
                                    case .grid:
                                        gridContent
                                    }
                                } else {
                                    emptyView
                                }
                            }
                        }
                    }
                    .refreshable {
                        await startContentLoad(forceRefresh: true)
                    }
                )
            .onChange(of: geometry.size.width, initial: true) { _, newWidth in
                viewWidth = newWidth
            }
        }
        .navigationTitle(instance.displayName)
        #if !os(tvOS)
        .toolbarTitleDisplayMode(.inlineLarge)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showViewOptions = true
                } label: {
                    Label(String(localized: "viewOptions.title"), systemImage: "slider.horizontal.3")
                }
                .liquidGlassTransitionSource(id: "instanceBrowseViewOptions", in: sheetTransition)
            }
        }
        .sheet(isPresented: $showViewOptions) {
            ViewOptionsSheet(
                layout: $layout,
                rowStyle: $rowStyle,
                gridColumns: $gridColumnCount,
                hideWatched: $hideWatched,
                maxGridColumns: gridConfig.maxColumns
            )
            .liquidGlassSheetContent(sourceID: "instanceBrowseViewOptions", in: sheetTransition)
        }
        .task {
            // Initialize search view model
            if let appEnvironment {
                searchViewModel = SearchViewModel(
                    instance: instance,
                    contentService: appEnvironment.contentService,
                    deArrowProvider: appEnvironment.deArrowBrandingProvider,
                    dataManager: appEnvironment.dataManager,
                    settingsManager: appEnvironment.settingsManager
                )
            }
            
            // Check login status for instances that support authentication
            if instance.supportsAuthentication {
                isLoggedIn = appEnvironment?.credentialsManager(for: instance)?.isLoggedIn(for: instance) ?? false
            }
            
            // Set initial tab only once (not on navigation back)
            if !hasInitializedTab {
                hasInitializedTab = true
                if let initialTab {
                    selectedTab = initialTab
                } else if instance.supportsAuthentication && isLoggedIn {
                    // Default to Feed tab when logged in
                    selectedTab = .feed
                }
            }
            
            // Load watch entries for hide watched feature
            loadWatchEntries()
            
            await startContentLoad()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
            loadWatchEntries()
        }
        .onChange(of: selectedTab) { _, _ in
            isLoading = true
            errorMessage = nil
            Task { await startContentLoad() }
        }
        #if os(iOS)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: Text(String(localized: "instance.browse.search.placeholder"))
        )
        #else
        .searchable(
            text: $searchText,
            prompt: Text(String(localized: "instance.browse.search.placeholder"))
        )
        #endif
        .onSubmit(of: .search) {
            searchViewModel?.cancelSuggestions()
            Task {
                await searchViewModel?.search(query: searchText)
            }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                searchViewModel?.clearResults()
            } else {
                searchViewModel?.fetchSuggestions(for: newValue)
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            SearchFiltersSheet(onApply: {
                Task {
                    await searchViewModel?.search(query: searchText)
                }
            }, filters: Binding(
                get: { searchViewModel?.filters ?? .defaults },
                set: { searchViewModel?.filters = $0 }
            ))
            #if !os(tvOS)
            .presentationDetents([.medium, .large])
            #endif
        }
    }

    // MARK: - Computed Properties

    private var availableTabs: [BrowseTab] {
        if instance.supportsFeed && isLoggedIn {
            // Playlists tab only available for Invidious (Piped playlists to be added in future)
            if instance.type == .invidious {
                return [.feed, .popular, .trending, .playlists]
            }
            return [.feed, .popular, .trending]
        }
        return [.popular, .trending]
    }

    private var currentVideos: [Video] {
        var videos: [Video]
        switch selectedTab {
        case .popular: videos = popularVideos
        case .trending: videos = trendingVideos
        case .feed: videos = filteredFeedVideos
        case .playlists: videos = []  // Playlists tab doesn't show videos directly
        }
        
        // Filter out watched videos if enabled
        if hideWatched {
            videos = videos.filter { video in
                guard let entry = watchEntriesMap[video.id.videoID] else { return true }
                return !entry.isFinished
            }
        }
        
        return videos
    }

    private var filteredFeedVideos: [Video] {
        if let channelID = selectedFeedChannelID {
            return feedVideos.filter { $0.author.id == channelID }
        }
        return feedVideos
    }

    private var isInSearchMode: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    // Grid layout configuration
    private var gridConfig: GridLayoutConfiguration {
        GridLayoutConfiguration(viewWidth: viewWidth, gridColumns: gridColumnCount)
    }
    
    /// Gets the watch progress (0.0-1.0) for a video, or nil if not watched/finished.
    private func watchProgress(for video: Video) -> Double? {
        guard let entry = watchEntriesMap[video.id.videoID] else { return nil }
        let progress = entry.progress
        // Only show progress bar for partially watched videos
        return progress > 0 && progress < 1 ? progress : nil
    }

    /// Subscriptions sorted by most recent video upload date
    private var sortedFeedSubscriptions: [Channel] {
        var latestVideoDate: [String: Date] = [:]
        for video in feedVideos {
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

        return feedSubscriptions.sorted { (sub1: Channel, sub2: Channel) -> Bool in
            let channelID1 = sub1.id.channelID
            let channelID2 = sub2.id.channelID
            let date1 = latestVideoDate[channelID1] ?? .distantPast
            let date2 = latestVideoDate[channelID2] ?? .distantPast
            return date1 > date2
        }
    }

    // MARK: - Search Filters Strip

    private var searchFiltersStrip: some View {
        HStack(spacing: 12) {
            // Filter button
            Button {
                showFilterSheet = true
            } label: {
                Image(systemName: (searchViewModel?.filters.isDefault ?? true)
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill")
                    .font(.title2)
            }

            // Content type segmented picker
            Picker("", selection: Binding(
                get: { searchViewModel?.filters.type ?? .video },
                set: { searchViewModel?.filters.type = $0 }
            )) {
                ForEach(SearchContentType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onChange(of: searchViewModel?.filters.type) { _, _ in
            Task {
                await searchViewModel?.search(query: searchText)
            }
        }
    }

    // MARK: - Feed Channel Filter Strip

    private var feedChannelFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(sortedFeedSubscriptions) { subscription in
                    ChannelFilterChip(
                        channelID: subscription.id.channelID,
                        name: subscription.name,
                        avatarURL: subscription.thumbnailURL,
                        serverURL: yatteeServerURL,
                        isSelected: selectedFeedChannelID == subscription.id.channelID,
                        avatarSize: 44,
                        onTap: {
                            if selectedFeedChannelID == subscription.id.channelID {
                                selectedFeedChannelID = nil
                            } else {
                                selectedFeedChannelID = subscription.id.channelID
                            }
                        },
                        onGoToChannel: {
                            appEnvironment?.navigationCoordinator.navigate(
                                to: .channel(subscription.id.channelID, .global(provider: ContentSource.youtubeProvider))
                            )
                        },
                        onUnsubscribe: nil,
                        authHeader: avatarAuthHeader
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        #if os(tvOS)
        .background(Color.black.opacity(0.3))
        #else
        .background(.bar)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
        #endif
    }

    // MARK: - List Layout

    @ViewBuilder
    private var listContent: some View {
        VideoListContent(listStyle: listStyle) {
            ForEach(Array(currentVideos.enumerated()), id: \.element.id) { index, video in
                VideoListRow(
                    isLast: index == currentVideos.count - 1,
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
                        queueSource: selectedTab == .feed ? .subscriptions(continuation: nil) : .manual,
                        sourceLabel: selectedTab.title,
                        videoList: currentVideos,
                        videoIndex: index
                    )
                }
                #if !os(tvOS)
                .videoSwipeActions(video: video)
                #endif
            }

            // Feed tab load more
            if selectedTab == .feed {
                LoadMoreTrigger(
                    isLoading: isLoadingMoreFeed,
                    hasMore: hasMoreFeedResults && feedVideos.count > feedLoadedVideoCount
                ) {
                    loadMoreFeedResults()
                }
            }
        }
    }
    
    // MARK: - Grid Layout

    @ViewBuilder
    private var gridContent: some View {
        VideoGridContent(columns: gridConfig.effectiveColumns) {
            ForEach(Array(currentVideos.enumerated()), id: \.element.id) { index, video in
                VideoCardView(
                    video: video,
                    watchProgress: watchProgress(for: video),
                    isCompact: gridConfig.isCompactCards
                )
                .tappableVideo(
                    video,
                    queueSource: selectedTab == .feed ? .subscriptions(continuation: nil) : .manual,
                    sourceLabel: selectedTab.title,
                    videoList: currentVideos,
                    videoIndex: index
                )
                .onAppear {
                    // Infinite scroll for feed tab - trigger when near end AND we have new content since last trigger
                    if selectedTab == .feed
                        && index >= currentVideos.count - 3
                        && hasMoreFeedResults
                        && !isLoadingMoreFeed
                        && feedVideos.count > feedLoadedVideoCount {
                        loadMoreFeedResults()
                    }
                }
            }
        }

        if selectedTab == .feed && isLoadingMoreFeed {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
        }
    }

    // MARK: - Playlists Layout

    @ViewBuilder
    private var playlistsListContent: some View {
        VideoListContent(listStyle: listStyle) {
            ForEach(Array(userPlaylists.enumerated()), id: \.element.id) { index, playlist in
                VideoListRow(
                    isLast: index == userPlaylists.count - 1,
                    rowStyle: rowStyle,
                    listStyle: listStyle
                ) {
                    NavigationLink(value: NavigationDestination.playlist(.remote(playlist.id, instance: instance, title: playlist.title))) {
                        SearchPlaylistRowView(playlist: playlist, style: rowStyle)
                            .contentShape(Rectangle())
                    }
                    .zoomTransitionSource(id: playlist.id)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var playlistsGridContent: some View {
        VideoGridContent(columns: gridConfig.effectiveColumns) {
            ForEach(userPlaylists) { playlist in
                NavigationLink(value: NavigationDestination.playlist(.remote(playlist.id, instance: instance, title: playlist.title))) {
                    PlaylistCardView(playlist: playlist, isCompact: gridConfig.isCompactCards)
                        .contentShape(Rectangle())
                }
                .zoomTransitionSource(id: playlist.id)
                .buttonStyle(.plain)
            }
        }
    }

    private var playlistsEmptyView: some View {
        ContentUnavailableView {
            Label(String(localized: "playlists.empty.title"), systemImage: "play.square.stack")
        } description: {
            Text(String(localized: "playlists.empty.description"))
        }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        ContentUnavailableView {
            Label(String(localized: "common.noContent"), systemImage: "tray")
        } description: {
            Text(String(localized: "instance.browse.noVideos"))
        }
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        ContentUnavailableView {
            Label(String(localized: "common.error"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button(String(localized: "common.retry")) {
                Task { await startContentLoad(forceRefresh: true) }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsContent: some View {
        if let vm = searchViewModel {
            switch layout {
            case .list:
                searchResultsListContent(vm: vm)
            case .grid:
                searchResultsGridContent(vm: vm)
            }
        }
    }
    
    @ViewBuilder
    private func searchResultsListContent(vm: SearchViewModel) -> some View {
        VideoListContent(listStyle: listStyle) {
            ForEach(Array(vm.resultItems.enumerated()), id: \.element.id) { resultIndex, item in
                VideoListRow(
                    isLast: resultIndex == vm.resultItems.count - 1,
                    rowStyle: rowStyle,
                    listStyle: listStyle,
                    contentWidth: item.isChannel ? rowStyle.thumbnailHeight : nil
                ) {
                    switch item {
                    case .video(let video, let videoIndex):
                        VideoRowView(
                            video: video,
                            style: rowStyle,
                            watchProgress: watchProgress(for: video)
                        )
                        .tappableVideo(
                            video,
                            queueSource: .search(query: searchText, continuation: nil),
                            sourceLabel: String(localized: "queue.source.search \(searchText)"),
                            videoList: vm.videos,
                            videoIndex: videoIndex
                        )
                        #if !os(tvOS)
                        .videoSwipeActions(video: video)
                        #endif
                        .onAppear {
                            if resultIndex >= vm.resultItems.count - 3 {
                                Task { await vm.loadMore() }
                            }
                        }

                    case .playlist(let playlist):
                        NavigationLink(value: NavigationDestination.playlist(.remote(playlist.id, instance: instance, title: playlist.title))) {
                            SearchPlaylistRowView(playlist: playlist, style: rowStyle)
                                .contentShape(Rectangle())
                        }
                        .zoomTransitionSource(id: playlist.id)
                        .buttonStyle(.plain)
                        .onAppear {
                            if resultIndex >= vm.resultItems.count - 3 {
                                Task { await vm.loadMore() }
                            }
                        }

                    case .channel(let channel):
                        NavigationLink(
                            value: NavigationDestination.channel(
                                channel.id.channelID,
                                channel.id.source
                            )
                        ) {
                            ChannelRowView(channel: channel, style: rowStyle)
                                .contentShape(Rectangle())
                        }
                        .zoomTransitionSource(id: channel.id.channelID)
                        .buttonStyle(.plain)
                        .onAppear {
                            if resultIndex >= vm.resultItems.count - 3 {
                                Task { await vm.loadMore() }
                            }
                        }
                    }
                }
            }

            LoadMoreTrigger(
                isLoading: vm.isLoadingMore,
                hasMore: vm.hasMoreResults
            ) {
                Task { await vm.loadMore() }
            }
        }
    }
    
    @ViewBuilder
    private func searchResultsGridContent(vm: SearchViewModel) -> some View {
        VideoGridContent(columns: gridConfig.effectiveColumns) {
            ForEach(Array(vm.resultItems.enumerated()), id: \.element.id) { resultIndex, item in
                switch item {
                case .video(let video, let videoIndex):
                    VideoCardView(
                        video: video,
                        watchProgress: watchProgress(for: video),
                        isCompact: gridConfig.isCompactCards
                    )
                    .tappableVideo(
                        video,
                        queueSource: .search(query: searchText, continuation: nil),
                        sourceLabel: String(localized: "queue.source.search \(searchText)"),
                        videoList: vm.videos,
                        videoIndex: videoIndex
                    )
                    .onAppear {
                        if resultIndex >= vm.resultItems.count - 3 {
                            Task { await vm.loadMore() }
                        }
                    }

                case .playlist(let playlist):
                    NavigationLink(value: NavigationDestination.playlist(.remote(playlist.id, instance: instance, title: playlist.title))) {
                        PlaylistCardView(playlist: playlist, isCompact: gridConfig.isCompactCards)
                            .contentShape(Rectangle())
                    }
                    .zoomTransitionSource(id: playlist.id)
                    .buttonStyle(.plain)
                    .onAppear {
                        if resultIndex >= vm.resultItems.count - 3 {
                            Task { await vm.loadMore() }
                        }
                    }

                case .channel(let channel):
                    NavigationLink(
                        value: NavigationDestination.channel(
                            channel.id.channelID,
                            channel.id.source
                        )
                    ) {
                        ChannelCardGridView(channel: channel, isCompact: gridConfig.isCompactCards)
                            .contentShape(Rectangle())
                    }
                    .zoomTransitionSource(id: channel.id.channelID)
                    .buttonStyle(.plain)
                    .onAppear {
                        if resultIndex >= vm.resultItems.count - 3 {
                            Task { await vm.loadMore() }
                        }
                    }
                }
            }
        }

        if vm.isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
        }
    }

    private var searchHintView: some View {
        ContentUnavailableView {
            Label(String(localized: "search.hint.title"), systemImage: "magnifyingglass")
        } description: {
            Text(String(localized: "search.hint.description"))
        }
    }

    @ViewBuilder
    private var suggestionsView: some View {
        if let vm = searchViewModel {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(vm.suggestions, id: \.self) { suggestion in
                    Button {
                        dismissKeyboard()
                        searchText = suggestion
                        Task { await vm.search(query: suggestion) }
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            Text(suggestion)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.leading)
                }
            }
        }
    }

    private var searchEmptyView: some View {
        ContentUnavailableView {
            Label(String(localized: "search.noResults.title"), systemImage: "magnifyingglass")
        } description: {
            Text(String(localized: "search.noResults.description"))
        }
    }

    private func searchErrorView(_ error: String) -> some View {
        ContentUnavailableView {
            Label(String(localized: "common.error"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button(String(localized: "common.retry")) {
                Task { await searchViewModel?.search(query: searchText) }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Data Loading
    
    private func loadWatchEntries() {
        watchEntriesMap = appEnvironment?.dataManager.watchEntriesMap() ?? [:]
    }

    private func startContentLoad(forceRefresh: Bool = false) async {
        // Cancel any in-flight load before starting a new one
        contentLoadTask?.cancel()
        let task = Task {
            await performLoadContent(forceRefresh: forceRefresh)
        }
        contentLoadTask = task
        await task.value
    }

    private func performLoadContent(forceRefresh: Bool = false) async {
        guard let appEnvironment else {
            errorMessage = "App not initialized"
            isLoading = false
            return
        }

        // Skip loading if we already have data and not forcing refresh
        let hasData: Bool
        switch selectedTab {
        case .popular: hasData = !popularVideos.isEmpty
        case .trending: hasData = !trendingVideos.isEmpty
        case .feed: hasData = !feedVideos.isEmpty
        case .playlists: hasData = !userPlaylists.isEmpty
        }

        if hasData && !forceRefresh {
            isLoading = false
            return
        }

        isLoading = !hasData  // Only show loading spinner when no existing data
        errorMessage = nil

        do {
            switch selectedTab {
            case .popular:
                let videos = try await appEnvironment.contentService.popular(for: instance)
                popularVideos = videos
                prefetchBranding(for: videos)
            case .trending:
                let videos = try await appEnvironment.contentService.trending(for: instance)
                trendingVideos = videos
                prefetchBranding(for: videos)
            case .feed:
                guard let credential = appEnvironment.credentialsManager(for: instance)?.credential(for: instance) else {
                    errorMessage = String(localized: "feed.error.notLoggedIn")
                    isLoading = false
                    return
                }

                if forceRefresh {
                    feedPage = 1
                    hasMoreFeedResults = true
                    // Don't clear feedVideos here — keep old data visible
                    // until the API call succeeds and replaces it.
                }

                // Load subscriptions and feed based on instance type
                let subscriptionChannels: [Channel]
                let videos: [Video]

                switch instance.type {
                case .invidious:
                    let api = InvidiousAPI(httpClient: appEnvironment.httpClient)

                    // Load subscriptions for channel filter
                    async let subscriptionsTask = api.subscriptions(instance: instance, sid: credential)

                    // Load feed
                    async let feedTask = api.feed(instance: instance, sid: credential, page: feedPage)

                    let (subscriptions, feedResponse) = try await (subscriptionsTask, feedTask)

                    // Fetch channel thumbnails in parallel (subscriptions API doesn't include them)
                    let enrichedSubscriptions = await fetchChannelThumbnails(
                        for: subscriptions,
                        instance: instance,
                        api: api
                    )

                    subscriptionChannels = enrichedSubscriptions.map { $0.toChannel(baseURL: instance.url) }
                    videos = feedResponse.videos
                    hasMoreFeedResults = feedResponse.hasMore

                case .piped:
                    let api = PipedAPI(httpClient: appEnvironment.httpClient)

                    // Load subscriptions and feed in parallel
                    async let subscriptionsTask = api.subscriptions(instance: instance, authToken: credential)
                    async let feedTask = api.feed(instance: instance, authToken: credential)

                    let (pipedSubscriptions, feedVideos) = try await (subscriptionsTask, feedTask)

                    subscriptionChannels = pipedSubscriptions.map { $0.toChannel() }
                    videos = feedVideos
                    // Piped doesn't support pagination for feed
                    hasMoreFeedResults = false

                default:
                    errorMessage = String(localized: "feed.error.notSupported")
                    isLoading = false
                    return
                }

                feedSubscriptions = subscriptionChannels.map { $0.enrichedThumbnail(using: appEnvironment.dataManager) }
                feedVideos = videos
                prefetchBranding(for: videos)
            case .playlists:
                // Playlists are currently only supported for Invidious
                guard instance.type == .invidious else {
                    errorMessage = String(localized: "feed.error.notSupported")
                    isLoading = false
                    return
                }

                guard let credential = appEnvironment.credentialsManager(for: instance)?.credential(for: instance) else {
                    errorMessage = String(localized: "feed.error.notLoggedIn")
                    isLoading = false
                    return
                }

                let api = InvidiousAPI(httpClient: appEnvironment.httpClient)
                let playlists = try await api.userPlaylists(instance: instance, sid: credential)
                userPlaylists = playlists
            }
        } catch is CancellationError {
            // Task was cancelled — another load is taking over, don't touch state
            return
        } catch let error as APIError where error == .cancelled {
            // HTTP request was cancelled — another load is taking over, don't touch state
            return
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func prefetchBranding(for videos: [Video]) {
        guard let appEnvironment else { return }
        let youtubeIDs = videos.compactMap { video -> String? in
            if case .global = video.id.source { return video.id.videoID }
            return nil
        }
        appEnvironment.deArrowBrandingProvider.prefetch(videoIDs: youtubeIDs)
    }

    /// Fetches channel thumbnails for subscriptions, using cache when available.
    /// Only fetches from network for channels not already cached.
    private func fetchChannelThumbnails(
        for subscriptions: [InvidiousSubscription],
        instance: Instance,
        api: InvidiousAPI
    ) async -> [InvidiousSubscription] {
        guard let credentialsManager = appEnvironment?.invidiousCredentialsManager else {
            return subscriptions
        }

        // Build initial thumbnail map from cache
        var thumbnailMap: [String: URL] = [:]
        for subscription in subscriptions {
            if let cachedURL = credentialsManager.thumbnailURL(forChannelID: subscription.authorId) {
                thumbnailMap[subscription.authorId] = cachedURL
            }
        }

        // Find channels that need fetching
        let allChannelIDs = subscriptions.map(\.authorId)
        let uncachedIDs = Set(credentialsManager.uncachedChannelIDs(from: allChannelIDs))

        // Fetch only uncached channels in parallel
        if !uncachedIDs.isEmpty {
            let fetchedThumbnails = await withTaskGroup(of: (String, URL?).self) { group in
                for subscription in subscriptions where uncachedIDs.contains(subscription.authorId) {
                    group.addTask {
                        do {
                            let channel = try await api.channel(id: subscription.authorId, instance: instance)
                            return (subscription.authorId, channel.thumbnailURL)
                        } catch {
                            return (subscription.authorId, nil)
                        }
                    }
                }

                var results: [String: URL] = [:]
                for await (authorId, thumbnailURL) in group {
                    if let url = thumbnailURL {
                        results[authorId] = url
                    }
                }
                return results
            }

            // Merge fetched thumbnails and cache them
            for (channelID, url) in fetchedThumbnails {
                thumbnailMap[channelID] = url
            }

            // Save to cache on main actor
            await MainActor.run {
                credentialsManager.setThumbnailURLs(fetchedThumbnails)
            }
        }

        // Create enriched subscriptions with thumbnails
        return subscriptions.map { subscription in
            var enriched = subscription
            enriched.thumbnailURL = thumbnailMap[subscription.authorId]
            return enriched
        }
    }

    private func loadMoreFeedResults() {
        guard hasMoreFeedResults, !isLoadingMoreFeed, !isLoading else { return }
        guard let appEnvironment,
              let sid = appEnvironment.invidiousCredentialsManager.sid(for: instance) else { return }

        isLoadingMoreFeed = true
        feedLoadedVideoCount = feedVideos.count  // Mark current count to prevent re-triggering
        feedPage += 1

        Task {
            do {
                let api = InvidiousAPI(httpClient: appEnvironment.httpClient)
                let feedResponse = try await api.feed(instance: instance, sid: sid, page: feedPage)

                await MainActor.run {
                    feedVideos.append(contentsOf: feedResponse.videos)
                    hasMoreFeedResults = feedResponse.hasMore
                    isLoadingMoreFeed = false
                    prefetchBranding(for: feedResponse.videos)
                }
            } catch {
                await MainActor.run {
                    isLoadingMoreFeed = false
                }
            }
        }
    }

    private func dismissKeyboard() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

}

// MARK: - Preview

#Preview {
    NavigationStack {
        InstanceBrowseView(
            instance: Instance(
                type: .invidious,
                url: URL(string: "https://invidious.example.com")!,
                name: "Example Instance"
            )
        )
    }
    .appEnvironment(.preview)
}
