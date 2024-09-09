import Defaults
import Siesta
import SwiftUI

struct SearchView: View {
    private var query: SearchQuery?

    @State private var searchSortOrder = SearchQuery.SortOrder.relevance
    @State private var searchDate = SearchQuery.Date.any
    @State private var searchDuration = SearchQuery.Duration.any

    @State private var recentsChanged = false

    #if os(tvOS)
        @State private var searchDebounce = Debounce()
        @State private var recentsDebounce = Debounce()
        private var recents = RecentsModel.shared
    #endif

    @State private var favoriteItem: FavoriteItem?

    @Environment(\.navigationStyle) private var navigationStyle

    @ObservedObject private var accounts = AccountsModel.shared
    @ObservedObject private var state = SearchModel.shared
    private var favorites = FavoritesModel.shared
    private var navigation = NavigationModel.shared

    @Default(.recentlyOpened) private var recentlyOpened
    @Default(.saveRecents) private var saveRecents
    @Default(.showHome) private var showHome
    @Default(.searchListingStyle) private var searchListingStyle
    @Default(.showSearchSuggestions) private var showSearchSuggestions

    private var videos = [Video]()

    init(_ query: SearchQuery? = nil, videos: [Video] = []) {
        self.query = query
        self.videos = videos
    }

    #if os(iOS)
        var body: some View {
            VStack {
                VStack {
                    if accounts.app.supportsSearchSuggestions, state.query.query != state.queryText {
                        SearchSuggestions()
                            .opacity(state.queryText.isEmpty ? 0 : 1)
                    } else {
                        results
                    }
                }
                .backport
                .scrollDismissesKeyboardInteractively()
            }
            .environment(\.listingStyle, searchListingStyle)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if #available(iOS 15, *) {
                        FocusableSearchTextField()
                    } else {
                        SearchTextField()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    searchMenu
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .navigationTitle("Search")
            .onAppear {
                if let query {
                    state.queryText = query.query
                    state.resetQuery(query)
                    updateFavoriteItem()
                }

                if !videos.isEmpty {
                    state.store.replace(ContentItem.array(of: videos))
                }
            }
            .onChange(of: accounts.current) { _ in
                state.reloadQuery()
            }
            .onChange(of: state.queryText) { newQuery in
                if newQuery.isEmpty {
                    favoriteItem = nil
                    state.resetQuery()
                } else {
                    updateFavoriteItem()
                }
                state.loadSuggestions(newQuery)
            }
            .onChange(of: searchSortOrder) { order in
                state.changeQuery { query in
                    query.sortBy = order
                    updateFavoriteItem()
                }
            }
            .onChange(of: searchDate) { date in
                state.changeQuery { query in
                    query.date = date
                    updateFavoriteItem()
                }
            }
            .onChange(of: searchDuration) { duration in
                state.changeQuery { query in
                    query.duration = duration
                    updateFavoriteItem()
                }
            }
        }

    #elseif os(tvOS)
        var body: some View {
            VStack {
                ZStack {
                    results
                }
            }
            .environment(\.listingStyle, searchListingStyle)
            .onAppear {
                if let query {
                    state.queryText = query.query
                    state.resetQuery(query)
                    updateFavoriteItem()
                }

                if !videos.isEmpty {
                    state.store.replace(ContentItem.array(of: videos))
                }
            }
            .onChange(of: accounts.current) { _ in
                state.reloadQuery()
            }
            .onChange(of: state.queryText) { newQuery in
                if newQuery.isEmpty {
                    favoriteItem = nil
                    state.resetQuery()
                } else {
                    updateFavoriteItem()
                }
                if showSearchSuggestions {
                    state.loadSuggestions(newQuery)
                }
                searchDebounce.invalidate()
                recentsDebounce.invalidate()

                searchDebounce.debouncing(2) {
                    state.changeQuery { query in
                        query.query = newQuery
                    }
                }

                recentsDebounce.debouncing(10) {
                    recents.addQuery(newQuery)
                }
            }
            .onChange(of: searchSortOrder) { order in
                state.changeQuery { query in
                    query.sortBy = order
                    updateFavoriteItem()
                }
            }
            .onChange(of: searchDate) { date in
                state.changeQuery { query in
                    query.date = date
                    updateFavoriteItem()
                }
            }
            .onChange(of: searchDuration) { duration in
                state.changeQuery { query in
                    query.duration = duration
                    updateFavoriteItem()
                }
            }
            .searchable(text: $state.queryText) {
                if !state.queryText.isEmpty {
                    ForEach(state.querySuggestions, id: \.self) { suggestion in
                        Text(suggestion)
                            .searchCompletion(suggestion)
                    }
                }
            }
        }

    #elseif os(macOS)
        var body: some View {
            ZStack {
                results
                if accounts.app.supportsSearchSuggestions, state.query.query != state.queryText, showSearchSuggestions {
                    HStack {
                        Spacer()
                        SearchSuggestions()
                            .borderLeading(width: 1, color: Color("ControlsBorderColor"))
                            .frame(maxWidth: 262)
                            .opacity(state.queryText.isEmpty ? 0 : 1)
                    }
                }
            }
            .environment(\.listingStyle, searchListingStyle)
            .toolbar {
                ToolbarItemGroup(placement: toolbarPlacement) {
                    ListingStyleButtons(listingStyle: $searchListingStyle)
                    HideWatchedButtons()
                    HideShortsButtons()
                    FavoriteButton(item: favoriteItem)
                        .id(favoriteItem?.id)

                    if accounts.app.supportsSearchFilters {
                        Section {
                            HStack {
                                Text("Sort:")
                                    .foregroundColor(.secondary)
                                searchSortOrderPicker
                            }
                        }
                        .transaction { t in t.animation = .none }
                    }

                    if accounts.app.supportsSearchFilters {
                        filtersMenu
                    }

                    if #available(macOS 12, *) {
                        FocusableSearchTextField()
                    } else {
                        SearchTextField()
                    }
                }
            }
            .onAppear {
                if let query {
                    state.queryText = query.query
                    state.resetQuery(query)
                    updateFavoriteItem()
                }

                if !videos.isEmpty {
                    state.store.replace(ContentItem.array(of: videos))
                }
            }
            .onChange(of: accounts.current) { _ in
                state.reloadQuery()
            }
            .onChange(of: state.queryText) { newQuery in
                if newQuery.isEmpty {
                    favoriteItem = nil
                    state.resetQuery()
                } else {
                    updateFavoriteItem()
                }
                state.loadSuggestions(newQuery)
            }
            .onChange(of: searchSortOrder) { order in
                state.changeQuery { query in
                    query.sortBy = order
                    updateFavoriteItem()
                }
            }
            .onChange(of: searchDate) { date in
                state.changeQuery { query in
                    query.date = date
                    updateFavoriteItem()
                }
            }
            .onChange(of: searchDuration) { duration in
                state.changeQuery { query in
                    query.duration = duration
                    updateFavoriteItem()
                }
            }
            .frame(minWidth: Constants.contentViewMinWidth)
            .navigationTitle("Search")
        }
    #endif

    #if os(iOS)
        var searchMenu: some View {
            Menu {
                if accounts.app.supportsSearchFilters {
                    searchSortOrderPicker
                        .pickerStyle(.menu)

                    Picker(selection: $searchDuration, label: Text("Duration")) {
                        ForEach(SearchQuery.Duration.allCases) { duration in
                            Text(duration.name).tag(duration)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Upload date", selection: $searchDate) {
                        ForEach(SearchQuery.Date.allCases) { date in
                            Text(date.name).tag(date)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if !state.query.isEmpty {
                    Section {
                        FavoriteButton(item: favoriteItem)
                    }
                }

                ListingStyleButtons(listingStyle: $searchListingStyle)

                Section {
                    HideWatchedButtons()
                    HideShortsButtons()
                }

                Section {
                    SettingsButtons()
                }
            } label: {
                HStack {
                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundColor(.accentColor)
                        .imageScale(.large)
                }
            }
        }
    #endif

    private var results: some View {
        VStack {
            if showRecentQueries {
                recentQueries
            } else {
                VerticalCells(items: state.store.collection, allowEmpty: state.query.isEmpty) {
                    if shouldDisplayHeader {
                        header
                    }
                }
                .environment(\.loadMoreContentHandler) { state.loadNextPage() }

                if noResults {
                    Text("No results")

                    if searchFiltersActive {
                        Button("Reset search filters", action: resetFilters)
                    }

                    Spacer()
                }
            }
        }
    }

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
            accounts.app.supportsSearchFilters || favorites.isEnabled ? .bottomBar : .automatic
        #else
            .automatic
        #endif
    }

    private var showRecentQueries: Bool {
        navigationStyle == .tab && saveRecents && state.queryText.isEmpty
    }

    private var filtersActive: Bool {
        searchDuration != .any || searchDate != .any
    }

    private func resetFilters() {
        searchSortOrder = .relevance
        searchDate = .any
        searchDuration = .any
    }

    private var noResults: Bool {
        state.store.collection.isEmpty && !state.isLoading && !state.query.isEmpty
    }

    private var recentQueries: some View {
        VStack {
            List {
                Section(header: Text("Recents")) {
                    if recentlyOpened.isEmpty {
                        Text("Search history is empty")
                            .foregroundColor(.secondary)
                    }
                    ForEach(recentlyOpened.reversed(), id: \.tag) { item in
                        recentItemControl(item)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundColor(.accentColor)
                    }
                }
                .redrawOn(change: recentsChanged)

                Section(footer: Color.clear.frame(minHeight: 80)) {
                    clearHistoryButton
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    @ViewBuilder private func recentItemControl(_ item: RecentItem) -> some View {
        #if os(tvOS)
            recentItemButton(item)
        #else
            if recentItemIsNavigationLink(item) {
                recentItemNavigationLink(item)
            } else {
                recentItemButton(item)
            }
        #endif
    }

    private func recentItemNavigationLink(_ item: RecentItem) -> some View {
        NavigationLink(destination: recentItemNavigationLinkDestination(item)) {
            recentItemLabel(item)
        }
        .contextMenu { recentItemContextMenu(item) }
    }

    @ViewBuilder private func recentItemNavigationLinkDestination(_ item: RecentItem) -> some View {
        switch item.type {
        case .channel:
            if let channel = item.channel {
                ChannelVideosView(channel: channel)
            }
        case .playlist:
            if let playlist = item.playlist {
                ChannelPlaylistView(playlist: playlist)
            }
        default:
            EmptyView()
        }
    }

    func recentItemIsNavigationLink(_ item: RecentItem) -> Bool {
        switch item.type {
        case .channel:
            return navigationStyle == .tab
        case .playlist:
            return navigationStyle == .tab
        default:
            return false
        }
    }

    private func recentItemButton(_ item: RecentItem) -> some View {
        Button {
            switch item.type {
            case .query:
                state.queryText = item.title
                state.changeQuery { query in query.query = item.title }
                NavigationModel.shared.hideKeyboard()

                updateFavoriteItem()
                RecentsModel.shared.add(item)
            case .channel:
                guard let channel = item.channel else {
                    return
                }

                NavigationModel.shared.openChannel(
                    channel,
                    navigationStyle: navigationStyle
                )
            case .playlist:
                guard let playlist = item.playlist else {
                    return
                }

                NavigationModel.shared.openChannelPlaylist(
                    playlist,
                    navigationStyle: navigationStyle
                )
            }
        } label: {
            recentItemLabel(item)
        }
        .contextMenu { recentItemContextMenu(item) }
    }

    private func recentItemContextMenu(_ item: RecentItem) -> some View {
        Group {
            removeButton(item)

            #if os(tvOS)
                Button("Cancel", role: .cancel) {}
            #endif
        }
    }

    private func recentItemLabel(_ item: RecentItem) -> some View {
        let systemImage = item.type == .query ? "magnifyingglass" :
            item.type == .channel ? RecentsModel.symbolSystemImage(item.title) :
            "list.and.film"
        return Label(item.title, systemImage: systemImage)
    }

    private func removeButton(_ item: RecentItem) -> some View {
        Button {
            RecentsModel.shared.close(item)
            recentsChanged.toggle()
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    private var clearHistoryButton: some View {
        Button {
            NavigationModel.shared.presentAlert(
                Alert(
                    title: Text("Are you sure you want to clear search history?"),
                    message: Text("This cannot be reverted"),
                    primaryButton: .destructive(Text("Clear")) {
                        RecentsModel.shared.clear()
                        recentsChanged.toggle()
                    },
                    secondaryButton: .cancel()
                )
            )
        } label: {
            Label("Clear Search History...", systemImage: "trash.fill")
        }
        .labelStyle(.titleOnly)
        .foregroundColor(Color("AppRedColor"))
    }

    private var searchFiltersActive: Bool {
        searchDate != .any || searchDuration != .any
    }

    private var searchSortOrderPicker: some View {
        Picker("Sort", selection: $searchSortOrder) {
            ForEach(SearchQuery.SortOrder.allCases) { sortOrder in
                Text(sortOrder.name).tag(sortOrder)
            }
        }
    }

    #if os(tvOS)
        private var searchSortOrderButton: some View {
            Button(action: { self.searchSortOrder = self.searchSortOrder.next() }) { Text(self.searchSortOrder.name)
                .font(.system(size: 30))
                .padding(.horizontal)
                .padding(.vertical, 2)
            }
            .buttonStyle(.card)
            .contextMenu {
                ForEach(SearchQuery.SortOrder.allCases) { sortOrder in
                    Button(sortOrder.name) {
                        self.searchSortOrder = sortOrder
                    }
                }
            }
        }

        private var searchDateButton: some View {
            Button(action: { self.searchDate = self.searchDate.next() }) {
                Text(self.searchDate.name)
                    .font(.system(size: 30))
                    .padding(.horizontal)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.card)
            .contextMenu {
                ForEach(SearchQuery.Date.allCases) { searchDate in
                    Button(searchDate.name) {
                        self.searchDate = searchDate
                    }
                }
            }
        }

        private var searchDurationButton: some View {
            Button(action: { self.searchDuration = self.searchDuration.next() }) {
                Text(self.searchDuration.name)
                    .font(.system(size: 30))
                    .padding(.horizontal)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.card)
            .contextMenu {
                ForEach(SearchQuery.Duration.allCases) { searchDuration in
                    Button(searchDuration.name) {
                        self.searchDuration = searchDuration
                    }
                }
            }
        }

        private var filtersHorizontalStack: some View {
            HStack {
                HStack(spacing: 30) {
                    Text("Sort")
                        .foregroundColor(.secondary)
                    searchSortOrderButton
                }
                .frame(maxWidth: 300, alignment: .trailing)

                HStack(spacing: 30) {
                    Text("Duration")
                        .foregroundColor(.secondary)
                    searchDurationButton
                }
                .frame(maxWidth: 300)

                HStack(spacing: 30) {
                    Text("Date")
                        .foregroundColor(.secondary)
                    searchDateButton
                }
                .frame(maxWidth: 300, alignment: .leading)
            }
            .font(.system(size: 30))
        }
    #else
        private var filtersMenu: some View {
            Menu(filtersActive ? "Filter: active" : "Filter") {
                Picker(selection: $searchDuration, label: Text("Duration")) {
                    ForEach(SearchQuery.Duration.allCases) { duration in
                        Text(duration.name).tag(duration)
                    }
                }

                Picker("Upload date", selection: $searchDate) {
                    ForEach(SearchQuery.Date.allCases) { date in
                        Text(date.name).tag(date)
                    }
                }
            }
            .foregroundColor(filtersActive ? .accentColor : .secondary)
            .transaction { t in t.animation = .none }
        }
    #endif

    private func updateFavoriteItem() {
        favoriteItem = FavoriteItem(section: .searchQuery(
            state.queryText,
            searchDate.rawValue,
            searchDuration.rawValue,
            searchSortOrder.rawValue
        ))
    }

    var shouldDisplayHeader: Bool {
        #if os(tvOS)
            !state.query.isEmpty
        #else
            false
        #endif
    }

    var header: some View {
        HStack {
            clearButton

            #if os(tvOS)
                if accounts.app.supportsSearchFilters {
                    filtersHorizontalStack
                }
            #endif
            FavoriteButton(item: favoriteItem)
                .id(favoriteItem?.id)
                .labelStyle(.iconOnly)
                .font(.system(size: 25))

            Spacer()
            ListingStyleButtons(listingStyle: $searchListingStyle)
            HideWatchedButtons()
            HideShortsButtons()
        }
        .labelStyle(.iconOnly)
        .padding(.leading, 30)
        .padding(.bottom, 15)
        .padding(.trailing, 30)
    }

    var clearButton: some View {
        Button {
            state.queryText = ""
        } label: {
            Label("Clear", systemImage: "xmark")
                .labelStyle(.iconOnly)
        }
        .font(.caption)
    }
}

struct SearchView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SearchView(SearchQuery(query: "Is Google Evil"), videos: Video.fixtures(30))
                .injectFixtureEnvironmentObjects()
        }
    }
}
