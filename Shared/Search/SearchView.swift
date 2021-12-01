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
    #endif

    @State private var favoriteItem: FavoriteItem?

    @Environment(\.navigationStyle) private var navigationStyle

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SearchModel> private var state

    @Default(.saveRecents) private var saveRecents

    private var videos = [Video]()

    var items: [ContentItem] {
        state.store.collection.sorted { $0 < $1 }
    }

    init(_ query: SearchQuery? = nil, videos: [Video] = []) {
        self.query = query
        self.videos = videos
    }

    var body: some View {
        PlayerControlsView {
            #if os(iOS)
                VStack {
                    SearchTextField()

                    if state.query.query != state.queryText, !state.queryText.isEmpty, !state.querySuggestions.collection.isEmpty {
                        SearchSuggestions()
                    } else {
                        results
                    }
                }
            #else
                ZStack {
                    results

                    #if !os(tvOS)
                        if state.query.query != state.queryText, !state.queryText.isEmpty, !state.querySuggestions.collection.isEmpty {
                            HStack {
                                Spacer()
                                SearchSuggestions()
                                    .borderLeading(width: 1, color: Color("ControlsBorderColor"))
                                    .frame(maxWidth: 280)
                            }
                        }
                    #endif
                }
            #endif
        }
        .toolbar {
            #if !os(tvOS)
                ToolbarItemGroup(placement: toolbarPlacement) {
                    #if os(macOS)
                        if let favoriteItem = favoriteItem {
                            FavoriteButton(item: favoriteItem)
                                .id(favoriteItem.id)
                        }
                    #endif

                    if accounts.app.supportsSearchFilters {
                        Section {
                            #if os(macOS)
                                HStack {
                                    Text("Sort:")
                                        .foregroundColor(.secondary)

                                    searchSortOrderPicker
                                }
                            #else
                                Menu("Sort: \(searchSortOrder.name)") {
                                    searchSortOrderPicker
                                }
                            #endif
                        }
                        .transaction { t in t.animation = .none }
                    }

                    #if os(iOS)
                        Spacer()

                        if let favoriteItem = favoriteItem {
                            FavoriteButton(item: favoriteItem)
                                .id(favoriteItem.id)
                        }

                        Spacer()
                    #endif

                    if accounts.app.supportsSearchFilters {
                        filtersMenu
                    }

                    #if os(macOS)
                        SearchTextField()
                    #endif
                }
            #endif
        }
        .onAppear {
            if query != nil {
                state.queryText = query!.query
                state.resetQuery(query!)
                updateFavoriteItem()
            }

            if !videos.isEmpty {
                state.store.replace(ContentItem.array(of: videos))
            }
        }
        .onChange(of: state.query.query) { newQuery in
            if newQuery.isEmpty {
                favoriteItem = nil
            } else {
                updateFavoriteItem()
            }
        }
        .onChange(of: state.queryText) { newQuery in
            if newQuery.isEmpty {
                state.resetQuery()
            }

            state.loadSuggestions(newQuery)

            #if os(tvOS)
                searchDebounce.invalidate()
                recentsDebounce.invalidate()

                searchDebounce.debouncing(2) {
                    state.changeQuery { query in
                        query.query = newQuery
                        updateFavoriteItem()
                    }
                }

                recentsDebounce.debouncing(10) {
                    recents.addQuery(newQuery)
                }
            #endif
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
        #if os(tvOS)
        .searchable(text: $state.queryText) {
            ForEach(state.querySuggestions.collection, id: \.self) { suggestion in
                Text(suggestion)
                    .searchCompletion(suggestion)
            }
        }
        #else
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .navigationTitle("Search")
        #endif
        #if os(iOS)
        .navigationBarHidden(!Defaults[.visibleSections].isEmpty || navigationStyle == .sidebar)
        #endif
    }

    private var results: some View {
        VStack {
            if showRecentQueries {
                recentQueries
            } else {
                #if os(tvOS)
                    ScrollView(.vertical, showsIndicators: false) {
                        HStack(spacing: 0) {
                            if accounts.app.supportsSearchFilters {
                                filtersHorizontalStack
                            }

                            if let favoriteItem = favoriteItem {
                                FavoriteButton(item: favoriteItem)
                                    .id(favoriteItem.id)
                                    .labelStyle(.iconOnly)
                                    .font(.system(size: 25))
                            }
                        }

                        HorizontalCells(items: items)
                    }
                    .edgesIgnoringSafeArea(.horizontal)
                #else
                    VerticalCells(items: items)
                #endif

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
            .bottomBar
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
        items.isEmpty && !state.isLoading && !state.query.isEmpty
    }

    private var recentQueries: some View {
        VStack {
            List {
                Section(header: Text("Recents")) {
                    if recentItems.isEmpty {
                        Text("Search history is empty")
                            .foregroundColor(.secondary)
                    }
                    ForEach(recentItems) { item in
                        Button(item.title) {
                            state.queryText = item.title
                            state.changeQuery { query in query.query = item.title }
                            updateFavoriteItem()
                        }
                        .contextMenu {
                            deleteButton(item)
                            deleteAllButton
                        }
                    }
                }
                .redrawOn(change: recentsChanged)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private func deleteButton(_ item: RecentItem) -> some View {
        Button {
            recents.close(item)
            recentsChanged.toggle()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var deleteAllButton: some View {
        Button {
            recents.clearQueries()
            recentsChanged.toggle()
        } label: {
            Label("Delete All", systemImage: "trash.fill")
        }
    }

    private var searchFiltersActive: Bool {
        searchDate != .any || searchDuration != .any
    }

    private var recentItems: [RecentItem] {
        Defaults[.recentlyOpened].filter { $0.type == .query }.reversed()
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
            state.query.query,
            state.query.date?.rawValue ?? "",
            state.query.duration?.rawValue ?? "",
            state.query.sortBy.rawValue
        ))
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
