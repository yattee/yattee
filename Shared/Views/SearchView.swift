import Defaults
import Siesta
import SwiftUI

struct SearchView: View {
    private var query: SearchQuery?

    @State private var searchSortOrder = SearchQuery.SortOrder.relevance
    @State private var searchDate = SearchQuery.Date.any
    @State private var searchDuration = SearchQuery.Duration.any

    @State private var presentingClearConfirmation = false
    @State private var recentsChanged = false

    #if os(tvOS)
        @State private var searchDebounce = Debounce()
        @State private var recentsDebounce = Debounce()
    #endif

    @Environment(\.navigationStyle) private var navigationStyle

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SearchModel> private var state

    private var videos = [Video]()

    init(_ query: SearchQuery? = nil, videos: [Video] = [Video]()) {
        self.query = query
        self.videos = videos
    }

    var body: some View {
        PlayerControlsView {
            VStack {
                if showRecentQueries {
                    recentQueries
                } else {
                    #if os(tvOS)
                        ScrollView(.vertical, showsIndicators: false) {
                            if accounts.app.supportsSearchFilters {
                                filtersHorizontalStack
                            }

                            VideosCellsHorizontal(videos: state.store.collection)
                        }
                        .edgesIgnoringSafeArea(.horizontal)
                    #else
                        VideosCellsVertical(videos: state.store.collection)
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
        .toolbar {
            #if !os(tvOS)
                ToolbarItemGroup(placement: toolbarPlacement) {
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

                        Spacer()

                        filtersMenu
                    }
                }
            #endif
        }
        .onAppear {
            if query != nil {
                state.queryText = query!.query
                state.resetQuery(query!)
            }

            if !videos.isEmpty {
                state.store.replace(videos)
            }
        }
        .searchable(text: $state.queryText, placement: searchFieldPlacement) {
            ForEach(state.querySuggestions.collection, id: \.self) { suggestion in
                Text(suggestion)
                    .searchCompletion(suggestion)
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
                    state.changeQuery { query in query.query = newQuery }
                }

                recentsDebounce.debouncing(10) {
                    recents.addQuery(newQuery)
                }
            #endif
        }
        .onSubmit(of: .search) {
            state.changeQuery { query in query.query = state.queryText }
            recents.addQuery(state.queryText)
        }
        .onChange(of: searchSortOrder) { order in
            state.changeQuery { query in query.sortBy = order }
        }
        .onChange(of: searchDate) { date in
            state.changeQuery { query in query.date = date }
        }
        .onChange(of: searchDuration) { duration in
            state.changeQuery { query in query.duration = duration }
        }
        #if !os(tvOS)
            .navigationTitle("Search")
        #endif
    }

    var searchFieldPlacement: SearchFieldPlacement {
        #if os(iOS)
            .navigationBarDrawer(displayMode: .always)
        #else
            .automatic
        #endif
    }

    var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
            .bottomBar
        #else
            .automatic
        #endif
    }

    fileprivate var showRecentQueries: Bool {
        navigationStyle == .tab && state.queryText.isEmpty
    }

    fileprivate var filtersActive: Bool {
        searchDuration != .any || searchDate != .any
    }

    fileprivate func resetFilters() {
        searchSortOrder = .relevance
        searchDate = .any
        searchDuration = .any
    }

    fileprivate var noResults: Bool {
        state.store.collection.isEmpty && !state.isLoading && !state.query.isEmpty
    }

    var recentQueries: some View {
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
                        }
                        #if os(iOS)
                            .swipeActions(edge: .trailing) {
                                deleteButton(item)
                            }
                        #elseif os(tvOS)
                            .contextMenu {
                                deleteButton(item)
                            }
                        #endif
                    }
                }
                .redrawOn(change: recentsChanged)

                if !recentItems.isEmpty {
                    clearAllButton
                }
            }
        }
        #if os(iOS)
            .listStyle(.insetGrouped)
        #endif
    }

    #if !os(macOS)
        func deleteButton(_ item: RecentItem) -> some View {
            Button(role: .destructive) {
                recents.close(item)
                recentsChanged.toggle()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    #endif

    var clearAllButton: some View {
        Button("Clear All", role: .destructive) {
            presentingClearConfirmation = true
        }
        .confirmationDialog("Clear All", isPresented: $presentingClearConfirmation) {
            Button("Clear All", role: .destructive) {
                recents.clearQueries()
            }
        }
    }

    var searchFiltersActive: Bool {
        searchDate != .any || searchDuration != .any
    }

    var recentItems: [RecentItem] {
        Defaults[.recentlyOpened].filter { $0.type == .query }.reversed()
    }

    var searchSortOrderPicker: some View {
        Picker("Sort", selection: $searchSortOrder) {
            ForEach(SearchQuery.SortOrder.allCases) { sortOrder in
                Text(sortOrder.name).tag(sortOrder)
            }
        }
    }

    #if os(tvOS)
        var searchSortOrderButton: some View {
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

        var searchDateButton: some View {
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

        var searchDurationButton: some View {
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

        var filtersHorizontalStack: some View {
            HStack {
                HStack(spacing: 30) {
                    Text("Sort")
                        .foregroundColor(.secondary)
                    searchSortOrderButton
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                HStack(spacing: 30) {
                    Text("Duration")
                        .foregroundColor(.secondary)
                    searchDurationButton
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 30) {
                    Text("Date")
                        .foregroundColor(.secondary)
                    searchDateButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 30))
        }
    #else
        var filtersMenu: some View {
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
}

struct SearchView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SearchView(SearchQuery(query: "Is Google Evil"), videos: Video.fixtures(30))
                .injectFixtureEnvironmentObjects()
        }
    }
}
