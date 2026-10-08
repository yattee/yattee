//
//  InstanceBrowseView.swift
//  Yattee
//
//  Displays content (Popular/Trending) for a specific backend instance.
//

import SwiftUI

struct InstanceBrowseView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

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
    /// Which login the account-scoped content belongs to, so a page still in
    /// flight cannot be appended to the next one's feed.
    @State private var accountContentGeneration = 0
    /// Which account the displayed — or in-flight — account-scoped content is
    /// for, so a change of effective account can be noticed at all.
    @State private var accountContentAccountID: UUID?
    @State private var feedVideos: [Video] = []
    @State private var feedSubscriptions: [Channel] = []

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
    @State private var showEditInstance = false
    @State private var showRemoveConfirmation = false

    // Account actions raised from the three-dots menu. Same shapes as the
    // edit sheet's accounts section: a nil-account login target means
    // "create one", and the sign-out is held until its confirmation.
    @State private var loginTarget: AccountLoginTarget?
    @State private var pendingSignOut: Account?
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

    /// Auth header for avatar loading (uses Yattee Server for YouTube channel avatars)
    private var avatarAuthHeader: String? {
        guard let server = yatteeServer else { return nil }
        return appEnvironment?.basicAuthCredentialsManager.basicAuthHeader(for: server)
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

    private var viewOptionsSheetContent: some View {
        ViewOptionsSheet(
            layout: $layout,
            rowStyle: $rowStyle,
            gridColumns: $gridColumnCount,
            hideWatched: $hideWatched,
            maxGridColumns: gridConfig.maxColumns
        )
    }

    /// All accounts on this instance, in the accounts submenu.
    private var instanceAccounts: [Account] {
        appEnvironment?.accountsManager.accounts(forInstance: instance.id) ?? []
    }

    /// The account this screen's authenticated tabs actually use.
    private var effectiveAccount: Account? {
        appEnvironment?.account(forInstance: instance)
    }

    private func accountDisplayName(_ account: Account) -> String {
        appEnvironment?.dataContextValidator.displayName(for: account) ?? instance.displayName
    }

    /// Shared content of the three-dots menu: refresh and accounts on top,
    /// link actions and instance management below, view options last.
    @ViewBuilder
    private var instanceMenuContent: some View {
        Button {
            Task { await startContentLoad(forceRefresh: true) }
        } label: {
            Label(String(localized: "common.refresh"), systemImage: "arrow.clockwise")
        }

        if instance.supportsAuthentication {
            Divider()
            accountsMenuContent
        }

        #if !os(tvOS)
        Divider()

        Button {
            copyInstanceURL()
        } label: {
            Label(String(localized: "instance.browse.copyURL"), systemImage: "doc.on.doc")
        }

        Button {
            openURL(instance.browseURL)
        } label: {
            Label(String(localized: "instance.browse.openInBrowser"), systemImage: "safari")
        }
        #endif

        Divider()

        Button {
            showEditInstance = true
        } label: {
            Label(String(localized: "instance.browse.edit \(instance.displayName)"), systemImage: "pencil")
        }

        Button(role: .destructive) {
            showRemoveConfirmation = true
        } label: {
            Label(String(localized: "instance.browse.remove \(instance.displayName)"), systemImage: "trash")
        }

        Divider()

        Button {
            showViewOptions = true
        } label: {
            Label(String(localized: "viewOptions.title"), systemImage: "slider.horizontal.3")
        }
    }

    /// Sign-in entry when nobody is signed in; otherwise an accounts submenu
    /// that switches the data context, adds a login, or signs the current one
    /// out. Switching goes through the global context — the same semantics as
    /// the switcher — which this view already reacts to.
    @ViewBuilder
    private var accountsMenuContent: some View {
        if instanceAccounts.isEmpty {
            Button {
                loginTarget = .newAccount
            } label: {
                Label(String(localized: "login.loginToAccount"), systemImage: "person.badge.plus")
            }
        } else {
            Menu {
                ForEach(instanceAccounts) { account in
                    Button {
                        appEnvironment?.switchDataContext(to: .account(account.id))
                    } label: {
                        if account.id == effectiveAccount?.id {
                            Label(accountDisplayName(account), systemImage: "checkmark")
                        } else {
                            Text(accountDisplayName(account))
                        }
                    }
                    .disabled(account.id == effectiveAccount?.id)
                }

                Divider()

                Button {
                    loginTarget = .newAccount
                } label: {
                    Label(String(localized: "accounts.addAccount"), systemImage: "person.badge.plus")
                }

                if let active = effectiveAccount {
                    Button(role: .destructive) {
                        pendingSignOut = active
                    } label: {
                        Label(
                            String(localized: "instance.browse.signOut \(accountDisplayName(active))"),
                            systemImage: "rectangle.portrait.and.arrow.forward"
                        )
                    }
                }
            } label: {
                Label(String(localized: "accounts.title"), systemImage: "person.crop.circle")
            }
        }
    }

    private func copyInstanceURL() {
        #if os(iOS)
        UIPasteboard.general.string = instance.browseURL.absoluteString
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(instance.browseURL.absoluteString, forType: .string)
        #endif
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
        let backgroundStyle: ListBackgroundStyle = listStyle == .inset ? .grouped : .plain
        GeometryReader { geometry in
            #if os(tvOS)
            VStack(spacing: 0) {
                // tvOS: Search field, type filter, search filters, view options
                HStack(spacing: 24) {
                    TextField("instance.browse.search.placeholder", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            searchViewModel?.cancelSuggestions()
                            Task { await searchViewModel?.search(query: searchText) }
                        }

                    if isInSearchMode {
                        // Type filter
                        filterMenu(
                            title: (searchViewModel?.filters.type ?? .video).title,
                            selection: Binding(
                                get: { searchViewModel?.filters.type ?? .video },
                                set: { searchViewModel?.filters.type = $0 }
                            ),
                            options: SearchContentType.allCases,
                            labelForOption: { $0.title }
                        )

                        // Combined search filters menu
                        tvOSFiltersMenu
                    }

                    Menu {
                        instanceMenuContent
                    } label: {
                        Label(String(localized: "common.more"), systemImage: "ellipsis")
                    }
                }
                .focusSection()
                .padding(.horizontal, 48)
                .padding(.top, 20)
                .padding(.bottom, 20)
                // Content
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: 20)

                        // Tab picker (hidden during search)
                        if !isInSearchMode {
                            tabPicker
                                .padding()
                        }

                        // Content
                        Group {
                            if isInSearchMode, let vm = searchViewModel {
                                if !vm.hasSearched {
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
                .scrollClipDisabled()
                .refreshable {
                    await startContentLoad(forceRefresh: true)
                }
                .focusSection()
            }
            .onChange(of: geometry.size.width, initial: true) { _, newWidth in
                viewWidth = newWidth
            }
            #else
            backgroundStyle.color
                .ignoresSafeArea()
                .overlay(
                    ScrollView {
                        VStack(spacing: 0) {
                            // Tab picker (hidden during search; lives in the toolbar on macOS)
                            #if !os(macOS)
                            if !isInSearchMode {
                                tabPicker
                                    .padding()
                            }
                            #endif

                            // Feed channel filter strip (hidden during search)
                            if selectedTab == .feed && !feedSubscriptions.isEmpty && !isInSearchMode {
                                feedChannelFilterStrip
                            }

                            // Search filter strip (shown persistently after search submitted; lives in the toolbar on macOS)
                            #if !os(macOS)
                            if isInSearchMode && (searchViewModel?.hasSearched ?? false) && instance.supportsSearchFilters {
                                searchFiltersStrip
                            }
                            #endif

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
            #endif
        }
        #if !os(tvOS)
        .navigationTitle(instance.displayName)
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            // Instance menu first so it is the leftmost navigation item on macOS.
            ToolbarItem(placement: viewOptionsPlacement) {
                Menu {
                    instanceMenuContent
                } label: {
                    Label(String(localized: "common.more"), systemImage: "ellipsis")
                }
                .liquidGlassTransitionSource(id: "instanceBrowseViewOptions", in: sheetTransition)
                #if os(macOS)
                .popover(isPresented: $showViewOptions, arrowEdge: .bottom) {
                    viewOptionsSheetContent
                }
                #endif
            }
            #if os(macOS)
            if #available(macOS 26, *) {
                // Render the items bare (conditional `if`, no opacity/disabled
                // wrappers): wrapping a `.segmented` Picker inserts a hosting layer
                // that makes the toolbar fall back to a Liquid-Glass pill instead of
                // the native segmented control. The search filters button shows only
                // while displaying search results; the principal picker swaps between
                // the browse tab picker and the search content type picker.
                if showsSearchFiltersInToolbar {
                    ToolbarItem(placement: .navigation) {
                        searchFiltersToolbarButton
                    }
                }
                if isToolbarPickerVisible {
                    ToolbarItem(placement: .principal) {
                        if showsSearchFiltersInToolbar {
                            searchContentTypePicker
                        } else {
                            tabPicker
                        }
                    }
                }
            } else if showsSearchFiltersInToolbar {
                ToolbarItem(placement: .navigation) {
                    searchFiltersToolbarButton
                }
                ToolbarItem(placement: .principal) {
                    searchContentTypePicker
                        .fixedSize()
                }
            } else if !isInSearchMode {
                ToolbarItem(placement: .principal) {
                    tabPicker
                        .fixedSize()
                }
            }
            // Pin the trailing group (search field) to the right edge,
            // matching the global Search view.
            if #available(macOS 26, *) {
                ToolbarSpacer(.flexible, placement: .primaryAction)
            }
            #endif
        }
        #endif
        #if !os(macOS)
        .sheet(isPresented: $showViewOptions) {
            viewOptionsSheetContent
                .liquidGlassSheetContent(sourceID: "instanceBrowseViewOptions", in: sheetTransition)
        }
        #endif
        #if os(tvOS)
        .fullScreenCover(isPresented: $showEditInstance) {
            TVSidebarDetailContainer(systemImage: "pencil.circle", title: String(localized: "sources.editSource")) {
                EditSourceView(source: .remoteServer(instance))
            }
            .tvFullScreenCoverBackground()
        }
        #else
        .sheet(isPresented: $showEditInstance) {
            EditSourceView(source: .remoteServer(instance))
        }
        #endif
        .confirmationDialog(
            String(localized: "sources.delete.confirmation.single \(instance.displayName)"),
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                appEnvironment?.removeInstance(instance)
                dismiss()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            // The same cascade runs from here as from Settings, so the same
            // logins go with it.
            if let accounts = InstanceDeletionDisclosure.message(for: instance, in: appEnvironment) {
                Text(accounts)
            }
        }
        .platformSheet(item: $loginTarget) { target in
            InstanceLoginView(instance: instance, initialUsername: storedUsername(for: target)) { credential, username in
                storeLogin(credential: credential, username: username, target: target)
            }
        }
        .confirmationDialog(
            String(localized: "accounts.remove.confirm.title \(pendingSignOut.map(accountDisplayName) ?? instance.displayName)"),
            isPresented: Binding(
                get: { pendingSignOut != nil },
                set: { if !$0 { pendingSignOut = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.remove"), role: .destructive) {
                confirmSignOut()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                pendingSignOut = nil
            }
        } message: {
            Text(String(localized: "accounts.remove.confirm.message"))
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
            
            refreshLoginState()
            
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
        // A credential can arrive over iCloud Keychain, or an account be added,
        // while this stays on screen — the Feed tab depends on it and would
        // otherwise stay missing until the view was rebuilt. Either notification
        // can also move *which* account is effective here: a status change
        // because the resolution falls back to a sibling login on the same
        // instance, an add or a remove because it changes what there is to fall
        // back to. Content loaded for the previous one has to go with it.
        .onReceive(NotificationCenter.default.publisher(for: .accountStatusesDidChange)) { _ in
            handleEffectiveAccountChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountsDidChange)) { _ in
            handleEffectiveAccountChange()
        }
        // Selecting the other login on this instance changes whose feed and
        // playlists these are. Nothing else here would notice: the instance,
        // the tab and the "already has data" shortcut are all unchanged.
        .onReceive(NotificationCenter.default.publisher(for: .dataContextDidChange)) { _ in
            discardAccountScopedContent()
            refreshLoginState()
            if !resetSelectedTabIfUnavailable() {
                Task { await startContentLoad() }
            }
        }
        // Same reason, without the context moving: the credential behind this
        // instance's account was replaced.
        .onReceive(NotificationCenter.default.publisher(for: .accountCredentialDidChange)) { _ in
            discardAccountScopedContent()
            refreshLoginState()
            if !resetSelectedTabIfUnavailable() {
                Task { await startContentLoad() }
            }
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
        .onSubmit(of: .search) {
            searchViewModel?.cancelSuggestions()
            Task {
                await searchViewModel?.search(query: searchText)
            }
        }
        #elseif !os(tvOS)
        .searchable(
            text: $searchText,
            prompt: Text(String(localized: "instance.browse.search.placeholder"))
        )
        .onSubmit(of: .search) {
            searchViewModel?.cancelSuggestions()
            Task {
                await searchViewModel?.search(query: searchText)
            }
        }
        #endif
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                searchViewModel?.clearResults()
            } else {
                searchViewModel?.fetchSuggestions(for: newValue)
            }
        }
        #if !os(macOS)
        .sheet(isPresented: $showFilterSheet) {
            searchFiltersSheetContent
            #if !os(tvOS)
                .presentationDetents([.medium, .large])
            #endif
        }
        #endif
    }

    // MARK: - Computed Properties

    private var searchFiltersSheetContent: some View {
        SearchFiltersSheet(onApply: {
            Task {
                await searchViewModel?.search(query: searchText)
            }
        }, filters: Binding(
            get: { searchViewModel?.filters ?? .defaults },
            set: { searchViewModel?.filters = $0 }
        ))
    }

    #if os(macOS)
    private var isShowingSearchResults: Bool {
        isInSearchMode && (searchViewModel?.hasSearched ?? false)
    }

    private var showsSearchFiltersInToolbar: Bool {
        isShowingSearchResults && instance.supportsSearchFilters
    }

    private var isToolbarPickerVisible: Bool {
        // Tab picker stays visible while typing; it swaps to the search content
        // type picker only once a search has been submitted
        !isShowingSearchResults || showsSearchFiltersInToolbar
    }

    private var searchContentTypePicker: some View {
        Picker("", selection: Binding(
            get: { searchViewModel?.filters.type ?? .video },
            set: { searchViewModel?.filters.type = $0 }
        )) {
            ForEach(SearchContentType.allCases) { type in
                Text(type.title).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: searchViewModel?.filters.type) { _, _ in
            Task {
                await searchViewModel?.search(query: searchText)
            }
        }
    }

    private var searchFiltersToolbarButton: some View {
        Button {
            showFilterSheet = true
        } label: {
            Label(String(localized: "search.filters"), systemImage: (searchViewModel?.filters.isDefault ?? true)
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
        }
        .popover(isPresented: $showFilterSheet, arrowEdge: .bottom) {
            searchFiltersSheetContent
        }
    }
    #endif

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(availableTabs) { tab in
                #if os(macOS)
                // Labels render icon-only in a macOS toolbar segmented control
                Text(tab.title)
                    .tag(tab)
                #else
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
                #endif
            }
        }
        .pickerStyle(.segmented)
    }

    /// The account whose playlists the Playlists tab shows.
    private var playlistsAccount: Account? {
        appEnvironment?.account(forInstance: instance)
    }

    /// The account's playlists, read from the shared cache rather than fetched
    /// into this view.
    ///
    /// Everything that changes a server-side playlist goes through that cache —
    /// the picker that creates one while adding a video, the detail view that
    /// renames or deletes one — so reading it is what makes those changes show
    /// up here. It is keyed by account, which is also the discard on an account
    /// change: whose playlists these are moves with `playlistsAccount`.
    private var userPlaylists: [Playlist] {
        guard let appEnvironment, let account = playlistsAccount else { return [] }
        return appEnvironment.remotePlaylistsCache.playlists(for: account.id) ?? []
    }

    private var availableTabs: [BrowseTab] {
        if instance.supportsFeed && isLoggedIn {
            // Capabilities decide, never the instance type: a Piped account
            // reads its playlists through exactly the same service, so the tab
            // is offered wherever an account can actually fill it.
            if let account = playlistsAccount,
               appEnvironment?.accountsManager.capabilities(for: account)?.supportsPlaylistReads == true {
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
                    Task { await searchViewModel?.search(query: searchText) }
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
        }
    }

    private var tvOSFiltersMenu: some View {
        Menu {
            Menu(String(localized: "search.sort")) {
                ForEach(SearchSortOption.allCases) { option in
                    Button {
                        searchViewModel?.filters.sort = option
                        Task { await searchViewModel?.search(query: searchText) }
                    } label: {
                        if searchViewModel?.filters.sort == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            }

            Menu(String(localized: "search.uploadDate")) {
                ForEach(SearchDateFilter.allCases) { option in
                    Button {
                        searchViewModel?.filters.date = option
                        Task { await searchViewModel?.search(query: searchText) }
                    } label: {
                        if searchViewModel?.filters.date == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            }

            Menu(String(localized: "search.duration")) {
                ForEach(SearchDurationFilter.allCases) { option in
                    Button {
                        searchViewModel?.filters.duration = option
                        Task { await searchViewModel?.search(query: searchText) }
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

            Button(role: .destructive) {
                let currentType = searchViewModel?.filters.type ?? .video
                searchViewModel?.filters = .defaults
                searchViewModel?.filters.type = currentType
                Task { await searchViewModel?.search(query: searchText) }
            } label: {
                Label(String(localized: "search.filters.reset"), systemImage: "arrow.counterclockwise")
            }
            .disabled(searchViewModel?.filters.isDefault ?? true)
        } label: {
            Label(String(localized: "search.filters"), systemImage: "line.3.horizontal.decrease")
        }
    }
    #else
    private var searchFiltersStrip: some View {
        HStack(spacing: 12) {
            Button {
                showFilterSheet = true
            } label: {
                Image(systemName: (searchViewModel?.filters.isDefault ?? true)
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill")
                    .font(.title2)
            }

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
    #endif

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
                    // These are the account's own playlists, so the detail view
                    // is told whose they are — that is what lets it fetch them
                    // authenticated and offer to change them.
                    NavigationLink(value: NavigationDestination.playlist(
                        .remote(playlist.id, instance: instance, title: playlist.title, accountID: playlistsAccount?.id)
                    )) {
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
                NavigationLink(value: NavigationDestination.playlist(
                    .remote(playlist.id, instance: instance, title: playlist.title, accountID: playlistsAccount?.id)
                )) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        ContentUnavailableView {
            Label(String(localized: "common.noContent"), systemImage: "tray")
        } description: {
            Text(String(localized: "instance.browse.noVideos"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading
    
    /// Drops what belonged to the previously selected login.
    ///
    /// Public browsing — popular and trending — is unauthenticated and stays.
    /// The playlists are not listed here either: they are read from the shared
    /// cache under the account's own id, so they leave with the account.
    private func discardAccountScopedContent() {
        accountContentGeneration += 1
        feedVideos = []
        feedSubscriptions = []
        feedPage = 1
        hasMoreFeedResults = false
        isLoadingMoreFeed = false
        // The high-water mark belongs to the discarded feed. Left behind, it
        // gates pagination against the previous login's count: the next one
        // would have to exceed a page it never loaded before it could ask for
        // a second.
        feedLoadedVideoCount = 0
        accountContentAccountID = nil
    }

    /// Drops account-scoped content when the account it belongs to is no longer
    /// the one this instance resolves to.
    ///
    /// - Returns: whether anything was discarded, so the caller can reload.
    @discardableResult
    private func discardAccountScopedContentIfAccountChanged() -> Bool {
        guard let loadedFor = accountContentAccountID, loadedFor != playlistsAccount?.id else {
            return false
        }

        discardAccountScopedContent()
        return true
    }

    /// Handles a change to which account this instance resolves to, whatever
    /// moved it: a status, or an account being added or removed.
    private func handleEffectiveAccountChange() {
        let accountChanged = discardAccountScopedContentIfAccountChanged()
        refreshLoginState()

        // Moving off a tab that no longer exists reloads by itself.
        guard !resetSelectedTabIfUnavailable() else { return }

        if accountChanged {
            Task { await startContentLoad() }
        }
    }

    /// Moves off a tab that has just stopped being offered.
    ///
    /// The Feed and Playlists tabs exist only while an account backs them. When
    /// one goes away the picker drops it, and a selection left pointing at it
    /// leaves an unhighlighted tab strip over content nobody can reach.
    ///
    /// - Returns: whether the selection moved, which reloads through
    ///   `onChange(of: selectedTab)`.
    @discardableResult
    private func resetSelectedTabIfUnavailable() -> Bool {
        let tabs = availableTabs
        guard !tabs.contains(selectedTab), let first = tabs.first else { return false }

        selectedTab = first
        return true
    }

    private func refreshLoginState() {
        guard instance.supportsAuthentication else { return }
        isLoggedIn = appEnvironment?.isSignedIn(to: instance) ?? false
    }

    /// Files a successful login against an account, mirroring the edit sheet.
    @discardableResult
    private func storeLogin(credential: String, username: String, target: AccountLoginTarget) -> Bool {
        guard let appEnvironment else { return false }
        return AccountSignInHandler(appEnvironment: appEnvironment, instance: instance)
            .storeLogin(credential: credential, username: username, target: target)
    }

    /// The identifier an existing account last signed in with, when this device
    /// holds it. A new account has nobody to name yet.
    private func storedUsername(for target: AccountLoginTarget) -> String? {
        guard let account = target.account else { return nil }
        return appEnvironment?.accountCredentialsManager(for: account)?.username(for: account)
    }

    private func confirmSignOut() {
        guard let appEnvironment, let account = pendingSignOut else { return }
        defer { pendingSignOut = nil }

        // Re-resolved rather than trusted: the dialog can outlive the account,
        // which another device may have deleted while it was up.
        guard let account = appEnvironment.accountsManager.account(id: account.id) else { return }

        appEnvironment.signOutAndRemoveAccount(account)
    }

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
        // Never skipped: the list is a cache other screens change, and what was
        // already fetched stays on screen while it is refetched.
        case .playlists: hasData = false
        }

        if hasData && !forceRefresh {
            isLoading = false
            return
        }

        isLoading = !hasData  // Only show loading spinner when no existing data
        errorMessage = nil

        // Which login the account-scoped tabs are being loaded for. Cancelling
        // the previous task is not enough on its own: a request that already
        // came back races the cancellation, and its results would be installed
        // after the purge that was meant to remove them. Popular and trending
        // are unauthenticated and deliberately not fenced.
        let generation = accountContentGeneration

        // Recorded before the request goes out, not after it lands: an account
        // change while the fetch is in flight has to be able to see whose fetch
        // it was.
        if selectedTab == .feed || selectedTab == .playlists {
            accountContentAccountID = playlistsAccount?.id
        }

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
                guard let credential = appEnvironment.credential(forInstance: instance) else {
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
                let hasMore: Bool

                let contentService = appEnvironment.contentService

                switch instance.type {
                case .invidious:
                    // Load subscriptions for channel filter
                    async let subscriptionsTask = contentService.subscriptions(for: instance, credential: credential)

                    // Load feed
                    async let feedTask = contentService.feed(for: instance, credential: credential, page: feedPage)

                    let (subscriptions, feedResponse) = try await (subscriptionsTask, feedTask)

                    // Fetch channel thumbnails in parallel (subscriptions API doesn't include them)
                    subscriptionChannels = await fetchChannelThumbnails(
                        for: subscriptions,
                        instance: instance
                    )
                    videos = feedResponse.videos
                    hasMore = feedResponse.hasMore

                case .piped:
                    // Load subscriptions and feed in parallel
                    async let subscriptionsTask = contentService.subscriptions(for: instance, credential: credential)
                    async let feedTask = contentService.feed(for: instance, credential: credential)

                    let (pipedSubscriptions, feedVideos) = try await (subscriptionsTask, feedTask)

                    subscriptionChannels = pipedSubscriptions
                    videos = feedVideos
                    // Piped doesn't support pagination for feed
                    hasMore = false

                default:
                    errorMessage = String(localized: "feed.error.notSupported")
                    isLoading = false
                    return
                }

                guard generation == accountContentGeneration else { return }

                hasMoreFeedResults = hasMore
                feedSubscriptions = subscriptionChannels.map { $0.enrichedThumbnail(using: appEnvironment.dataManager) }
                feedVideos = videos
                prefetchBranding(for: videos)
            case .playlists:
                // Addressed by account rather than by instance and secret: the
                // cache resolves the credential through the service, and refuses
                // backends that cannot list playlists at all. Nothing is stored
                // here — the rows are read back out of the cache, which is what
                // lets a playlist created or deleted elsewhere show up.
                guard let account = playlistsAccount else {
                    errorMessage = String(localized: "feed.error.notLoggedIn")
                    isLoading = false
                    return
                }

                try await appEnvironment.remotePlaylistsCache.refreshList(for: account)
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
        for subscriptions: [Channel],
        instance: Instance
    ) async -> [Channel] {
        guard let appEnvironment else { return subscriptions }
        let credentialsManager = appEnvironment.invidiousCredentialsManager
        let contentService = appEnvironment.contentService

        // Build initial thumbnail map from cache
        var thumbnailMap: [String: URL] = [:]
        for subscription in subscriptions {
            if let cachedURL = credentialsManager.thumbnailURL(forChannelID: subscription.id.channelID) {
                thumbnailMap[subscription.id.channelID] = cachedURL
            }
        }

        // Find channels that need fetching
        let allChannelIDs = subscriptions.map(\.id.channelID)
        let uncachedIDs = Set(credentialsManager.uncachedChannelIDs(from: allChannelIDs))

        // Fetch only uncached channels in parallel
        if !uncachedIDs.isEmpty {
            let fetchedThumbnails = await withTaskGroup(of: (String, URL?).self) { group in
                for subscription in subscriptions where uncachedIDs.contains(subscription.id.channelID) {
                    let channelID = subscription.id.channelID
                    group.addTask {
                        do {
                            let channel = try await contentService.channel(id: channelID, instance: instance)
                            return (channelID, channel.thumbnailURL)
                        } catch {
                            return (channelID, nil)
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

        // Create enriched subscriptions with thumbnails. A fetched or cached
        // avatar wins over whatever the subscriptions listing carried, which is
        // the precedence the Invidious subscription conversion applied when this
        // ran over the raw listing.
        return subscriptions.map { subscription in
            guard let thumbnailURL = thumbnailMap[subscription.id.channelID] else {
                return subscription
            }
            return Channel(
                id: subscription.id,
                name: subscription.name,
                description: subscription.description,
                subscriberCount: subscription.subscriberCount,
                videoCount: subscription.videoCount,
                thumbnailURL: thumbnailURL,
                bannerURL: subscription.bannerURL,
                isVerified: subscription.isVerified
            )
        }
    }

    private func loadMoreFeedResults() {
        guard hasMoreFeedResults, !isLoadingMoreFeed, !isLoading else { return }
        guard let appEnvironment,
              let sid = appEnvironment.credential(forInstance: instance) else { return }

        isLoadingMoreFeed = true
        feedLoadedVideoCount = feedVideos.count  // Mark current count to prevent re-triggering
        feedPage += 1

        // The login can change while this page is in flight, and appending
        // afterwards would mix one account's private videos into another's
        // feed.
        let generation = accountContentGeneration

        Task {
            do {
                let feedResponse = try await appEnvironment.contentService.feed(
                    for: instance,
                    credential: sid,
                    page: feedPage
                )

                await MainActor.run {
                    guard generation == accountContentGeneration else { return }

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
