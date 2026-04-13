//
//  SearchView.swift
//  Yattee
//
//  Search tab with source filtering and results.
//

import SwiftUI

struct SearchView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Namespace private var sheetTransition

    /// Initial query for deep linking. When set, auto-executes search on appear.
    var initialQuery: String? = nil

    /// External search text binding (from CompactTabView iOS 18+ integration)
    private var externalSearchText: Binding<String>?

    /// Internal search text state (for standalone usage)
    @State private var internalSearchText = ""

    /// Computed binding to use external or internal search text
    private var searchTextBinding: Binding<String> {
        externalSearchText ?? $internalSearchText
    }

    @State private var showFilterSheet = false
    @State private var selectedSearchInstance: Instance?
    @State private var searchViewModel: SearchViewModel?
    @State private var searchHistory: [SearchHistory] = []
    @State private var recentChannels: [RecentChannel] = []
    @State private var recentPlaylists: [RecentPlaylist] = []
    @State private var showingClearAllRecentsConfirmation = false
    @State private var showViewOptions = false
    @State private var isSearchHistoryExpanded = false

    @AppStorage("searchFilters") private var savedFiltersData: Data?

    // Persisted search instance selection
    @AppStorage("searchInstanceID") private var savedSearchInstanceID: String?

    // View options (persisted, separate from subscriptions)
    @AppStorage("searchLayout") private var layout: VideoListLayout = .list
    @AppStorage("searchRowStyle") private var rowStyle: VideoRowStyle = .regular
    @AppStorage("searchGridColumns") private var gridColumns = 2
    @AppStorage("searchHideWatched") private var hideWatched = false

    /// List style from centralized settings.
    private var listStyle: VideoListStyle {
        appEnvironment?.settingsManager.listStyle ?? .inset
    }

    // Privacy toggle tracking (establishes @Observable observation)
    private var saveRecentSearches: Bool {
        appEnvironment?.settingsManager.saveRecentSearches ?? true
    }
    private var saveRecentChannels: Bool {
        appEnvironment?.settingsManager.saveRecentChannels ?? true
    }
    private var saveRecentPlaylists: Bool {
        appEnvironment?.settingsManager.saveRecentPlaylists ?? true
    }

    // Grid layout configuration
    @State private var viewWidth: CGFloat = 0
    private var gridConfig: GridLayoutConfiguration {
        GridLayoutConfiguration(viewWidth: viewWidth, gridColumns: gridColumns)
    }

    /// The instance to use for searching.
    /// Defaults to the active instance if none is explicitly selected.
    private var searchInstance: Instance? {
        selectedSearchInstance ?? appEnvironment?.instancesManager.activeInstance
    }

    /// All enabled instances available for searching.
    private var availableInstances: [Instance] {
        appEnvironment?.instancesManager.enabledInstances ?? []
    }

    private var hasResults: Bool {
        searchViewModel?.hasResults ?? false
    }

    private var hasSearched: Bool {
        searchViewModel?.hasSearched ?? false
    }

    /// Initialize SearchView with optional external search text binding
    init(searchText: Binding<String>? = nil, initialQuery: String? = nil) {
        self.externalSearchText = searchText
        self.initialQuery = initialQuery
    }

    var body: some View {
        tvOSOrDefaultContent
        .sheet(isPresented: $showFilterSheet) {
            SearchFiltersSheet(onApply: {
                if hasResults {
                    Task { await searchViewModel?.search(query: searchTextBinding.wrappedValue) }
                }
            }, filters: Binding(
                get: { searchViewModel?.filters ?? .defaults },
                set: { newFilters in
                    searchViewModel?.filters = newFilters
                    saveFilters(newFilters)
                }
            ))
            #if !os(tvOS)
            .presentationDetents([.medium, .large])
            #endif
        }
        .sheet(isPresented: $showViewOptions) {
            ViewOptionsSheet(
                layout: $layout,
                rowStyle: $rowStyle,
                gridColumns: $gridColumns,
                hideWatched: $hideWatched,
                maxGridColumns: gridConfig.maxColumns
            )
            #if !os(tvOS)
            .liquidGlassSheetContent(sourceID: "searchViewOptions", in: sheetTransition)
            #endif
        }
        .onChange(of: searchTextBinding.wrappedValue) { _, newValue in
            if newValue.isEmpty {
                searchViewModel?.clearResults()  // Clear everything when empty
                searchViewModel?.filters = .defaults
                saveFilters(.defaults)
            } else {
                // Clear results but keep suggestions visible until new ones load
                searchViewModel?.clearSearchResults()
                searchViewModel?.fetchSuggestions(for: newValue)
            }
        }
        .task {
            initializeViewModel()
        }
        .task(id: initialQuery) {
            // Auto-execute search when opened with an initial query
            if let query = initialQuery, !query.isEmpty, searchTextBinding.wrappedValue.isEmpty {
                searchTextBinding.wrappedValue = query
                searchViewModel?.cancelSuggestions()
                searchViewModel?.filters.type = .video
                if let filters = searchViewModel?.filters {
                    saveFilters(filters)
                }
                Task { await searchViewModel?.search(query: query) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .searchHistoryDidChange)) { _ in
            loadSearchHistory()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recentChannelsDidChange)) { _ in
            loadRecentChannels()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recentPlaylistsDidChange)) { _ in
            loadRecentPlaylists()
        }
        .onReceive(NotificationCenter.default.publisher(for: .instancesDidChange)) { _ in
            handleInstancesChanged()
        }
        .onChange(of: hideWatched) { _, newValue in
            searchViewModel?.hideWatchedVideos = newValue
        }
        .onChange(of: saveRecentSearches) { _, _ in
            loadSearchHistory()
        }
        .onChange(of: saveRecentChannels) { _, _ in
            loadRecentChannels()
        }
        .onChange(of: saveRecentPlaylists) { _, _ in
            loadRecentPlaylists()
        }
    }

    @ViewBuilder
    private var tvOSOrDefaultContent: some View {
        #if os(tvOS)
        VStack(spacing: 0) {
            // tvOS: Search field, type filter, search filters, view options
            HStack(spacing: 24) {
                TextField("search.placeholder", text: searchTextBinding)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        searchViewModel?.cancelSuggestions()
                        searchViewModel?.filters.type = .video
                        if let filters = searchViewModel?.filters {
                            saveFilters(filters)
                        }
                        Task { await searchViewModel?.search(query: searchTextBinding.wrappedValue) }
                    }

                // Type filter
                filterMenu(
                    title: String(localized: "search.filters.type"),
                    selection: Binding(
                        get: { searchViewModel?.filters.type ?? .video },
                        set: { searchViewModel?.filters.type = $0 }
                    ),
                    options: SearchContentType.allCases,
                    labelForOption: { $0.title }
                )

                // Combined search filters menu
                tvOSFiltersMenu

                Button {
                    showViewOptions = true
                } label: {
                    Label(String(localized: "viewOptions.title"), systemImage: "slider.horizontal.3")
                }
            }
            .focusSection()
            .padding(.horizontal, 48)
            .padding(.top, 20)
            searchContent
                .padding(.top, 20)
                .focusSection()
        }
        #else
        searchContent
        .navigationTitle(String(localized: "tabs.search"))
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showViewOptions = true
                } label: {
                    Label(String(localized: "viewOptions.title"), systemImage: "slider.horizontal.3")
                }
                .liquidGlassTransitionSource(id: "searchViewOptions", in: sheetTransition)
            }
        }
        .searchable(text: searchTextBinding, prompt: Text(String(localized: "search.placeholder")))
        .onSubmit(of: .search) {
            searchViewModel?.cancelSuggestions()
            searchViewModel?.filters.type = .video
            if let filters = searchViewModel?.filters {
                saveFilters(filters)
            }
            Task { await searchViewModel?.search(query: searchTextBinding.wrappedValue) }
        }
        #endif
    }

    @ViewBuilder
    private var searchContent: some View {
        Group {
            if searchTextBinding.wrappedValue.isEmpty {
                emptySearchView
            } else if let vm = searchViewModel {
                if !vm.hasSearched {
                    if !vm.suggestions.isEmpty && !hasResults {
                        suggestionsView
                    } else if vm.isFetchingSuggestions && !hasResults {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Spacer()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if vm.isSearching && !hasResults {
                    resultsViewWithLoading
                } else if let error = vm.errorMessage, !hasResults {
                    errorView(error)
                } else if hasResults {
                    resultsView
                } else {
                    noResultsView
                }
            } else {
                Spacer()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func initializeViewModel() {
        guard let appEnvironment, searchViewModel == nil else { return }

        // Restore persisted instance selection if available
        if selectedSearchInstance == nil, let savedID = savedSearchInstanceID,
           let savedUUID = UUID(uuidString: savedID),
           let restoredInstance = availableInstances.first(where: { $0.id == savedUUID }) {
            selectedSearchInstance = restoredInstance
        } else if selectedSearchInstance == nil, savedSearchInstanceID != nil {
            // Saved instance no longer exists, clear the saved ID
            savedSearchInstanceID = nil
        }

        guard let instance = searchInstance else { return }
        searchViewModel = SearchViewModel(
            instance: instance,
            contentService: appEnvironment.contentService,
            deArrowProvider: appEnvironment.deArrowBrandingProvider,
            dataManager: appEnvironment.dataManager,
            settingsManager: appEnvironment.settingsManager
        )
        searchViewModel?.hideWatchedVideos = hideWatched
        loadFilters()
        loadSearchHistory()
        loadRecentChannels()
        loadRecentPlaylists()
    }

    private func switchToInstance(_ instance: Instance) {
        guard let appEnvironment else { return }
        selectedSearchInstance = instance
        savedSearchInstanceID = instance.id.uuidString

        // Recreate ViewModel for new instance
        let hadResults = hasResults
        searchViewModel = SearchViewModel(
            instance: instance,
            contentService: appEnvironment.contentService,
            deArrowProvider: appEnvironment.deArrowBrandingProvider,
            dataManager: appEnvironment.dataManager,
            settingsManager: appEnvironment.settingsManager
        )
        searchViewModel?.hideWatchedVideos = hideWatched
        loadFilters()

        // Re-run search if we had results
        if hadResults {
            Task { await searchViewModel?.search(query: searchTextBinding.wrappedValue) }
        }
    }

    /// Handles instance list changes by invalidating stale references.
    private func handleInstancesChanged() {
        // Check if selected instance was removed
        if let selected = selectedSearchInstance,
           !availableInstances.contains(where: { $0.id == selected.id }) {
            selectedSearchInstance = nil
            savedSearchInstanceID = nil
        }

        // Check if the current VM's instance was removed
        if let vm = searchViewModel,
           !availableInstances.contains(where: { $0.id == vm.instance.id }) {
            searchViewModel = nil
            // Re-initialize with a valid instance
            initializeViewModel()
        }
    }

    private func loadFilters() {
        guard let data = savedFiltersData,
              let decoded = try? JSONDecoder().decode(SearchFilters.self, from: data) else {
            return
        }
        searchViewModel?.filters = decoded
    }

    private func saveFilters(_ filters: SearchFilters) {
        savedFiltersData = try? JSONEncoder().encode(filters)
    }

    // MARK: - Views

    /// Instance picker for selecting search source when multiple instances are available
    @ViewBuilder
    private var instancePickerView: some View {
        if availableInstances.count > 1 {
            HStack {
                Text(String(localized: "search.source.title"))
                    .font(.headline)
                    .padding(.leading, listStyle == .inset ? 8 : 0)

                Spacer()

                Menu {
                    ForEach(availableInstances, id: \.id) { instance in
                        Button {
                            switchToInstance(instance)
                        } label: {
                            if instance.id == searchInstance?.id {
                                Label(instance.displayName, systemImage: "checkmark")
                            } else {
                                Text(instance.displayName)
                            }
                        }
                    }
                } label: {
                    Text(searchInstance?.displayName ?? "")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(listStyle == .inset ? 4 : 0)
            .background(listStyle == .inset ? ListBackgroundStyle.card.color : .clear)
            .clipShape(.rect(cornerRadius: 10))
            .padding(.horizontal)
        }
    }

    #if !os(tvOS)
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
            if let filters = searchViewModel?.filters {
                saveFilters(filters)
            }
            Task {
                await searchViewModel?.search(query: searchTextBinding.wrappedValue)
            }
        }
    }
    #endif

    #if os(tvOS)
    private func filterMenu<T: Hashable & Identifiable & CaseIterable>(
        title: String,
        selection: Binding<T>,
        options: [T],
        labelForOption: @escaping (T) -> String
    ) -> some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection.wrappedValue = option
                    if let filters = searchViewModel?.filters {
                        saveFilters(filters)
                    }
                    Task { await searchViewModel?.search(query: searchTextBinding.wrappedValue) }
                } label: {
                    if option == selection.wrappedValue {
                        Label(labelForOption(option), systemImage: "checkmark")
                    } else {
                        Text(labelForOption(option))
                    }
                }
            }
        } label: {
            Text(title)
                .font(.caption)
        }
    }

    private var tvOSFiltersMenu: some View {
        Menu {
            // Sort By
            Menu(String(localized: "search.sort")) {
                ForEach(SearchSortOption.allCases) { option in
                    Button {
                        searchViewModel?.filters.sort = option
                        if let filters = searchViewModel?.filters { saveFilters(filters) }
                        Task { await searchViewModel?.search(query: searchTextBinding.wrappedValue) }
                    } label: {
                        if searchViewModel?.filters.sort == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            }

            // Upload Date
            Menu(String(localized: "search.uploadDate")) {
                ForEach(SearchDateFilter.allCases) { option in
                    Button {
                        searchViewModel?.filters.date = option
                        if let filters = searchViewModel?.filters { saveFilters(filters) }
                        Task { await searchViewModel?.search(query: searchTextBinding.wrappedValue) }
                    } label: {
                        if searchViewModel?.filters.date == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            }

            // Duration
            Menu(String(localized: "search.duration")) {
                ForEach(SearchDurationFilter.allCases) { option in
                    Button {
                        searchViewModel?.filters.duration = option
                        if let filters = searchViewModel?.filters { saveFilters(filters) }
                        Task { await searchViewModel?.search(query: searchTextBinding.wrappedValue) }
                    } label: {
                        if searchViewModel?.filters.duration == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            }

            Divider()

            // Reset
            Button(role: .destructive) {
                let currentType = searchViewModel?.filters.type ?? .video
                searchViewModel?.filters = .defaults
                searchViewModel?.filters.type = currentType
                if let filters = searchViewModel?.filters { saveFilters(filters) }
                Task { await searchViewModel?.search(query: searchTextBinding.wrappedValue) }
            } label: {
                Label(String(localized: "search.filters.reset"), systemImage: "arrow.counterclockwise")
            }
            .disabled(searchViewModel?.filters.isDefault ?? true)
        } label: {
            Label(String(localized: "search.filters"), systemImage: "line.3.horizontal.decrease")
                .font(.caption)
        }
    }
    #endif

    // MARK: - Search History Helpers

    private var displayedSearchHistory: [SearchHistory] {
        if isSearchHistoryExpanded || searchHistory.count <= 5 {
            return searchHistory
        } else {
            return Array(searchHistory.prefix(5))
        }
    }

    private var hasMoreSearchHistory: Bool {
        searchHistory.count > 5
    }

    private var emptySearchView: some View {
        Group {
            if searchHistory.isEmpty && recentChannels.isEmpty && recentPlaylists.isEmpty {
                // Empty state with icon
                VStack(spacing: 24) {
                    Spacer(minLength: 60)

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)

                    Text(String(localized: "search.empty.description"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Spacer()
                }
                .padding()
                .accessibilityLabel("search.empty")
            } else {
                // Recent searches, channels, and playlists in scrollable view
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                        // Instance picker at top when multiple instances available
                        instancePickerView

                        // Recent search queries section
                        if !searchHistory.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                // Header - tappable to expand/collapse when more than 5 items
                                Button {
                                    if hasMoreSearchHistory {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isSearchHistoryExpanded.toggle()
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(String(localized: "search.recentSearches.title"))
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if hasMoreSearchHistory {
                                            Image(systemName: isSearchHistoryExpanded ? "chevron.up" : "chevron.down")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(!hasMoreSearchHistory)
                                .padding(.horizontal)
                                .padding(.bottom, 8)

                                // Items
                                VStack(spacing: 0) {
                                    ForEach(displayedSearchHistory) { history in
                                        Button {
                                            executeSearch(history.query)
                                        } label: {
                                            HStack(spacing: 12) {
                                                Image(systemName: "clock.arrow.circlepath")
                                                    .foregroundStyle(.secondary)
                                                Text(history.query)
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                            }
                                            .padding(.horizontal, listStyle == .inset ? 16 : 0)
                                            .padding(.vertical, 12)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .swipeActions {
                                            SwipeAction(
                                                symbolImage: "trash",
                                                tint: .white,
                                                background: .red,
                                                font: .body,
                                                size: CGSize(width: 38, height: 38)
                                            ) { reset in
                                                deleteHistory(history)
                                                reset()
                                            }
                                        }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                deleteHistory(history)
                                            } label: {
                                                Label(String(localized: "common.delete"), systemImage: "trash")
                                            }
                                        }

                                        if history.id != displayedSearchHistory.last?.id {
                                            Divider()
                                                .padding(.leading, 52)
                                        }
                                    }
                                }
                                #if os(tvOS)
                                .background(.clear)
                                #else
                                .background(listStyle == .inset ? ListBackgroundStyle.card.color : Color.clear)
                                .clipShape(.rect(cornerRadius: listStyle == .inset ? 10 : 0))
                                #endif
                                .padding(.horizontal)
                            }
                        }

                        // Recent channels section
                        if !recentChannels.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                // Header
                                HStack {
                                    Text(String(localized: "search.recentChannels.title"))
                                        .font(.headline)
                                    Spacer()
                                }
                                .padding(.horizontal)

                                // Horizontal scroll
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 16) {
                                        ForEach(recentChannels) { recentChannel in
                                            NavigationLink(
                                                value: NavigationDestination.channel(
                                                    recentChannel.channelID,
                                                    sourceFromRawValue(
                                                        recentChannel.sourceRawValue,
                                                        instanceURL: recentChannel.instanceURLString
                                                    )
                                                )
                                            ) {
                                                ChannelCardGridView(
                                                    channel: channelFromRecent(recentChannel),
                                                    isCompact: false
                                                )
                                                .frame(width: 160)
                                            }
                                            .zoomTransitionSource(id: recentChannel.channelID)
                                            .buttonStyle(.plain)
                                            .contextMenu {
                                                Button(role: .destructive) {
                                                    deleteRecentChannel(recentChannel)
                                                } label: {
                                                    Label(String(localized: "common.delete"), systemImage: "trash")
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }

                        // Recent playlists section
                        if !recentPlaylists.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                // Header
                                HStack {
                                    Text(String(localized: "search.recentPlaylists.title"))
                                        .font(.headline)
                                    Spacer()
                                }
                                .padding(.horizontal)

                                // Horizontal scroll
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 16) {
                                        ForEach(recentPlaylists) { recentPlaylist in
                                            NavigationLink(value: NavigationDestination.playlist(.remote(playlistIDFromRecent(recentPlaylist), instance: nil, title: recentPlaylist.title))) {
                                                PlaylistCardView(
                                                    playlist: playlistFromRecent(recentPlaylist),
                                                    isCompact: false
                                                )
                                                .frame(width: 200)
                                            }
                                            .zoomTransitionSource(id: playlistIDFromRecent(recentPlaylist))
                                            .buttonStyle(.plain)
                                            .contextMenu {
                                                Button(role: .destructive) {
                                                    deleteRecentPlaylist(recentPlaylist)
                                                } label: {
                                                    Label(String(localized: "common.delete"), systemImage: "trash")
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }

                        // Clear All Recents button at bottom
                        Button {
                            showingClearAllRecentsConfirmation = true
                        } label: {
                            HStack(spacing: 6) {
                                Spacer()
                                Image(systemName: "trash")
                                Text(String(localized: "search.clearAllRecents"))
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                    }
                    .padding(.vertical)
                }
                .background(listStyle == .inset ? ListBackgroundStyle.grouped.color : ListBackgroundStyle.plain.color)
                .accessibilityLabel("search.recents")
                .confirmationDialog(
                    String(localized: "search.clearAllRecents.confirm"),
                    isPresented: $showingClearAllRecentsConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(String(localized: "search.clearAllRecents"), role: .destructive) {
                        clearAllRecents()
                    }
                    Button(String(localized: "common.cancel"), role: .cancel) {}
                }
                .presentationCompactAdaptation(.sheet)
            }
        }
    }

    @ViewBuilder
    private var suggestionsView: some View {
        if let vm = searchViewModel {
            List {
                ForEach(vm.suggestions, id: \.self) { suggestion in
                    Button {
                        dismissKeyboard()
                        searchTextBinding.wrappedValue = suggestion
                        vm.cancelSuggestions()
                        vm.filters.type = .video
                        saveFilters(vm.filters)
                        Task { await vm.search(query: suggestion) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            Text(suggestion)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
        }
    }

    private var noResultsView: some View {
        ContentUnavailableView {
            Label(String(localized: "search.noResults.title"), systemImage: "magnifyingglass")
        } description: {
            Text(String(localized: "search.noResults.description"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("search.noResults")
    }

    private func errorView(_ error: String) -> some View {
        ContentUnavailableView {
            Label(String(localized: "common.error"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button(String(localized: "common.retry")) {
                Task { await searchViewModel?.search(query: searchTextBinding.wrappedValue) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Queue source for search results
    private var searchQueueSource: QueueSource {
        let page = searchViewModel?.page ?? 1
        let continuationString = page > 1 ? String(page) : nil
        return .search(query: searchTextBinding.wrappedValue, continuation: continuationString)
    }

    /// Unified results combining all content types for display.
    /// Uses the API's original ordering when type is .all, otherwise prioritizes the selected type.
    private var unifiedResults: [SearchResultItem] {
        guard let vm = searchViewModel else { return [] }

        // For .all type, use resultItems which preserves API order
        if vm.filters.type == .all {
            return vm.resultItems
        }

        // For specific types, prioritize that type first
        var results: [SearchResultItem] = []

        switch vm.filters.type {
        case .video:
            // Show videos first, but also include any playlists/channels server returned
            for (index, video) in vm.videos.enumerated() {
                results.append(.video(video, index: index))
            }
            for playlist in vm.playlists {
                results.append(.playlist(playlist))
            }
            for channel in vm.channels {
                results.append(.channel(channel))
            }
        case .playlist:
            // Show playlists first, then any videos/channels server returned
            for playlist in vm.playlists {
                results.append(.playlist(playlist))
            }
            for (index, video) in vm.videos.enumerated() {
                results.append(.video(video, index: index))
            }
            for channel in vm.channels {
                results.append(.channel(channel))
            }
        case .channel:
            // Show channels first, then any videos/playlists server returned
            for channel in vm.channels {
                results.append(.channel(channel))
            }
            for (index, video) in vm.videos.enumerated() {
                results.append(.video(video, index: index))
            }
            for playlist in vm.playlists {
                results.append(.playlist(playlist))
            }
        case .all:
            // Already handled above
            break
        }

        return results
    }

    /// Background style based on layout and list style.
    private var resultsBackgroundStyle: ListBackgroundStyle {
        if layout == .list && listStyle == .inset {
            return .grouped
        } else {
            return .plain
        }
    }

    @ViewBuilder
    private var resultsViewWithLoading: some View {
        if searchViewModel != nil {
            resultsBackgroundStyle.color
                .ignoresSafeArea()
                .overlay(
                    ScrollView {
                        VStack(spacing: 16) {
                            #if !os(tvOS)
                            // Filter strip at top (only for instances that support search filters)
                            if searchInstance?.supportsSearchFilters == true {
                                searchFiltersStrip
                            }
                            #endif

                            // Loading indicator
                            ProgressView()
                                .accessibilityIdentifier("search.loading")
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }
                    }
                )
        }
    }

    @ViewBuilder
    private var resultsView: some View {
        if searchViewModel != nil {
            resultsBackgroundStyle.color
                .ignoresSafeArea()
                .overlay(
                    ScrollView {
                        if layout == .list {
                            listResultsContent
                        } else {
                            gridResultsContent
                        }
                    }
                    .accessibilityLabel("search.results")
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear {
                                    viewWidth = geometry.size.width
                                }
                                .onChange(of: geometry.size.width) { _, newWidth in
                                    viewWidth = newWidth
                                }
                        }
                    )
                )
        }
    }

    @ViewBuilder
    private var listResultsContent: some View {
        if searchViewModel != nil {
            if listStyle == .inset {
                insetListContent
            } else {
                plainListContent
            }
        }
    }

    @ViewBuilder
    private var insetListContent: some View {
        if let vm = searchViewModel {
            VStack(spacing: 0) {
                // Filter strip at top (only for instances that support search filters)
                #if !os(tvOS)
                if searchInstance?.supportsSearchFilters == true {
                    searchFiltersStrip
                }
                #endif

                // Card container
                VideoListContent(listStyle: .inset) {
                    ForEach(Array(unifiedResults.enumerated()), id: \.element.id) { resultIndex, item in
                        searchResultRow(item: item, resultIndex: resultIndex, vm: vm)
                    }

                    LoadMoreTrigger(
                        isLoading: vm.isLoadingMore || (vm.isSearching && vm.page == 1),
                        hasMore: vm.hasMoreResults
                    ) {
                        Task { await vm.loadMore() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var plainListContent: some View {
        if let vm = searchViewModel {
            VStack(spacing: 0) {
                // Filter strip at top (only for instances that support search filters)
                #if !os(tvOS)
                if searchInstance?.supportsSearchFilters == true {
                    searchFiltersStrip
                }
                #endif

                VideoListContent(listStyle: .plain) {
                    ForEach(Array(unifiedResults.enumerated()), id: \.element.id) { resultIndex, item in
                        searchResultRow(item: item, resultIndex: resultIndex, vm: vm)
                    }

                    LoadMoreTrigger(
                        isLoading: vm.isLoadingMore || (vm.isSearching && vm.page == 1),
                        hasMore: vm.hasMoreResults
                    ) {
                        Task { await vm.loadMore() }
                    }
                }
            }
        }
    }

    /// Single row for a search result item (video, playlist, or channel).
    @ViewBuilder
    private func searchResultRow(item: SearchResultItem, resultIndex: Int, vm: SearchViewModel) -> some View {
        VideoListRow(
            isLast: resultIndex == unifiedResults.count - 1,
            rowStyle: rowStyle,
            listStyle: listStyle,
            contentWidth: item.isChannel ? rowStyle.thumbnailHeight : nil
        ) {
            switch item {
            case .video(let video, let videoIndex):
                VideoRowView(video: video, style: rowStyle)
                    .tappableVideo(
                        video,
                        queueSource: searchQueueSource,
                        sourceLabel: String(localized: "queue.source.search \(searchTextBinding.wrappedValue)"),
                        videoList: vm.videos,
                        videoIndex: videoIndex,
                        loadMoreVideos: loadMoreSearchResultsCallback
                    )
                    #if !os(tvOS)
                    .videoSwipeActions(video: video)
                    #endif
                    .onAppear {
                        if resultIndex == unifiedResults.count - 3 {
                            Task { await vm.loadMore() }
                        }
                    }

            case .playlist(let playlist):
                NavigationLink(value: NavigationDestination.playlist(.remote(playlist.id, instance: nil, title: playlist.title))) {
                    SearchPlaylistRowView(playlist: playlist, style: rowStyle)
                        .contentShape(Rectangle())
                }
                .zoomTransitionSource(id: playlist.id)
                .buttonStyle(.plain)
                .onAppear {
                    if resultIndex == unifiedResults.count - 3 {
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
                    if resultIndex == unifiedResults.count - 3 {
                        Task { await vm.loadMore() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var gridResultsContent: some View {
        if let vm = searchViewModel {
            LazyVStack(spacing: 16) {
                // Filter strip at top (only for instances that support search filters)
                #if !os(tvOS)
                if searchInstance?.supportsSearchFilters == true {
                    searchFiltersStrip
                        .padding(.bottom, 8)
                }
                #endif

                // Single grid with mixed content preserving order
                VideoGridContent(columns: gridConfig.effectiveColumns) {
                    ForEach(Array(unifiedResults.enumerated()), id: \.element.id) { resultIndex, item in
                        switch item {
                        case .video(let video, let videoIndex):
                            VideoCardView(
                                video: video,
                                isCompact: gridConfig.isCompactCards
                            )
                            .frame(maxHeight: .infinity, alignment: .top)
                            .tappableVideo(
                                video,
                                queueSource: searchQueueSource,
                                sourceLabel: String(localized: "queue.source.search \(searchTextBinding.wrappedValue)"),
                                videoList: vm.videos,
                                videoIndex: videoIndex,
                                loadMoreVideos: loadMoreSearchResultsCallback
                            )
                            .onAppear {
                                if resultIndex == unifiedResults.count - 3 {
                                    Task { await vm.loadMore() }
                                }
                            }

                        case .playlist(let playlist):
                            NavigationLink(value: NavigationDestination.playlist(.remote(playlist.id, instance: nil, title: playlist.title))) {
                                PlaylistCardView(playlist: playlist, isCompact: gridConfig.isCompactCards)
                                    .frame(maxHeight: .infinity, alignment: .top)
                                    .contentShape(Rectangle())
                            }
                            .zoomTransitionSource(id: playlist.id)
                            .buttonStyle(.plain)
                            .onAppear {
                                if resultIndex == unifiedResults.count - 3 {
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
                                    .frame(maxHeight: .infinity, alignment: .top)
                                    .contentShape(Rectangle())
                            }
                            .zoomTransitionSource(id: channel.id.channelID)
                            .buttonStyle(.plain)
                            .onAppear {
                                if resultIndex == unifiedResults.count - 3 {
                                    Task { await vm.loadMore() }
                                }
                            }
                        }
                    }
                }

                // Loading indicator at bottom
                if vm.isLoadingMore || (vm.isSearching && vm.page == 1) {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
        }
    }

    private func dismissKeyboard() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    // MARK: - Search History Helpers

    private func loadSearchHistory() {
        guard appEnvironment?.settingsManager.saveRecentSearches != false else {
            searchHistory = []
            return
        }
        guard let limit = appEnvironment?.settingsManager.searchHistoryLimit else { return }
        searchHistory = appEnvironment?.dataManager.fetchSearchHistory(limit: limit) ?? []
    }

    private func deleteHistory(_ history: SearchHistory) {
        appEnvironment?.dataManager.deleteSearchQuery(history)
    }

    private func clearAllHistory() {
        appEnvironment?.dataManager.clearSearchHistory()
        isSearchHistoryExpanded = false
    }

    private func executeSearch(_ query: String) {
        dismissKeyboard()
        searchTextBinding.wrappedValue = query
        searchViewModel?.cancelSuggestions()
        searchViewModel?.filters.type = .video
        if let filters = searchViewModel?.filters {
            saveFilters(filters)
        }
        Task { await searchViewModel?.search(query: query) }
    }

    // MARK: - Recent Channels/Playlists Helpers

    private func loadRecentChannels() {
        guard appEnvironment?.settingsManager.saveRecentChannels != false else {
            recentChannels = []
            return
        }
        guard let limit = appEnvironment?.settingsManager.searchHistoryLimit else { return }
        recentChannels = appEnvironment?.dataManager.fetchRecentChannels(limit: limit) ?? []
    }

    private func loadRecentPlaylists() {
        guard appEnvironment?.settingsManager.saveRecentPlaylists != false else {
            recentPlaylists = []
            return
        }
        guard let limit = appEnvironment?.settingsManager.searchHistoryLimit else { return }
        recentPlaylists = appEnvironment?.dataManager.fetchRecentPlaylists(limit: limit) ?? []
    }

    private func deleteRecentChannel(_ channel: RecentChannel) {
        appEnvironment?.dataManager.deleteRecentChannel(channel)
    }

    private func deleteRecentPlaylist(_ playlist: RecentPlaylist) {
        appEnvironment?.dataManager.deleteRecentPlaylist(playlist)
    }

    private func clearAllRecentChannels() {
        appEnvironment?.dataManager.clearRecentChannels()
    }

    private func clearAllRecentPlaylists() {
        appEnvironment?.dataManager.clearRecentPlaylists()
    }

    private func clearAllRecents() {
        appEnvironment?.dataManager.clearSearchHistory()
        appEnvironment?.dataManager.clearRecentChannels()
        appEnvironment?.dataManager.clearRecentPlaylists()
        isSearchHistoryExpanded = false
    }

    /// Converts RecentChannel to Channel for display
    private func channelFromRecent(_ recent: RecentChannel) -> Channel {
        Channel(
            id: ChannelID(
                source: sourceFromRawValue(recent.sourceRawValue, instanceURL: recent.instanceURLString),
                channelID: recent.channelID
            ),
            name: recent.name,
            subscriberCount: recent.subscriberCount,
            thumbnailURL: recent.thumbnailURLString.flatMap { URL(string: $0) },
            isVerified: recent.isVerified
        )
    }

    /// Converts RecentPlaylist to Playlist for display
    private func playlistFromRecent(_ recent: RecentPlaylist) -> Playlist {
        Playlist(
            id: playlistIDFromRecent(recent),
            title: recent.title,
            author: Author(id: "", name: recent.authorName),
            videoCount: recent.videoCount,
            thumbnailURL: recent.thumbnailURLString.flatMap { URL(string: $0) }
        )
    }

    /// Reconstructs PlaylistID from RecentPlaylist
    private func playlistIDFromRecent(_ recent: RecentPlaylist) -> PlaylistID {
        PlaylistID(
            source: sourceFromRawValue(recent.sourceRawValue, instanceURL: recent.instanceURLString),
            playlistID: recent.playlistID
        )
    }

    /// Reconstructs ContentSource from raw values
    private func sourceFromRawValue(_ rawValue: String, instanceURL: String?) -> ContentSource {
        switch rawValue {
        case "global":
            return .global(provider: ContentSource.youtubeProvider)
        case "federated":
            if let urlString = instanceURL, let url = URL(string: urlString) {
                return .federated(provider: ContentSource.peertubeProvider, instance: url)
            }
            return .global(provider: ContentSource.youtubeProvider)
        case "extracted":
            if let urlString = instanceURL, let url = URL(string: urlString) {
                return .extracted(extractor: "generic", originalURL: url)
            }
            return .global(provider: ContentSource.youtubeProvider)
        default:
            return .global(provider: ContentSource.youtubeProvider)
        }
    }

    // MARK: - Video Queue Continuation

    @Sendable
    private func loadMoreSearchResultsCallback() async throws -> ([Video], String?) {
        guard let searchViewModel else {
            throw NSError(
                domain: "SearchView",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Search view model not initialized"]
            )
        }

        // Check if there are more results to load
        guard searchViewModel.hasMoreResults else {
            return ([], nil)
        }

        // Load more results using SearchViewModel's pagination
        await searchViewModel.loadMore()

        // Return newly loaded videos and next page as continuation
        let videos = searchViewModel.videos
        let nextPage = searchViewModel.page
        let hasMore = searchViewModel.hasMoreResults

        // Convert next page to continuation string (only if there are more results)
        let continuation = hasMore ? String(nextPage) : nil

        return (videos, continuation)
    }
}

// MARK: - Search Filters Sheet

struct SearchFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onApply: () -> Void

    @Binding var filters: SearchFilters

    var body: some View {
        NavigationStack {
            Form {
                // Sort, Upload Date, Duration in one section
                Section {
                    Picker(String(localized: "search.sort"), selection: $filters.sort) {
                        ForEach(SearchSortOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    Picker(String(localized: "search.uploadDate"), selection: $filters.date) {
                        ForEach(SearchDateFilter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    Picker(String(localized: "search.duration"), selection: $filters.duration) {
                        ForEach(SearchDurationFilter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }

                // Reset Button
                Section {
                    Button(role: .destructive) {
                        let currentType = filters.type
                        filters = .defaults
                        filters.type = currentType
                    } label: {
                        HStack {
                            Spacer()
                            Text(String(localized: "search.filters.reset"))
                            Spacer()
                        }
                    }
                    .disabled(filters.isDefault)
                }
            }
            .navigationTitle(String(localized: "search.filters"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.apply")) {
                        onApply()
                        dismiss()
                    }
                }
            }
        }
    }
}



// MARK: - Preview

#Preview {
    NavigationStack {
        SearchView()
    }
    .appEnvironment(.preview)
}
