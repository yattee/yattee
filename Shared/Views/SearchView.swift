import Defaults
import Siesta
import SwiftUI

struct SearchView: View {
    private var query: SearchQuery?

    @State private var searchSortOrder: SearchQuery.SortOrder = .relevance
    @State private var searchDate: SearchQuery.Date?
    @State private var searchDuration: SearchQuery.Duration?

    @State private var presentingClearConfirmation = false
    @State private var recentsChanged = false

    @Environment(\.navigationStyle) private var navigationStyle

    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SearchModel> private var state

    init(_ query: SearchQuery? = nil) {
        self.query = query
    }

    var body: some View {
        Group {
            if navigationStyle == .tab && state.queryText.isEmpty {
                VStack {
                    if !recentItems.isEmpty {
                        recentQueries
                    }
                }
            } else {
                VideosView(videos: state.store.collection)

                if state.store.collection.isEmpty && !state.isLoading && !state.query.isEmpty {
                    Text("No results")

                    if searchFiltersActive {
                        Button("Reset search filters") {
                            self.searchSortOrder = .relevance
                            self.searchDate = nil
                            self.searchDuration = nil
                        }
                    }

                    Spacer()
                }
            }
        }
        .toolbar {
            #if os(iOS)
                ToolbarItemGroup(placement: .bottomBar) {
                    Section {
                        if !state.queryText.isEmpty {
                            Text("Sort:")
                                .foregroundColor(.secondary)

                            Menu(searchSortOrder.name) {
                                ForEach(SearchQuery.SortOrder.allCases) { sortOrder in
                                    Button(sortOrder.name) {
                                        searchSortOrder = sortOrder
                                    }
                                }
                            }

                            Spacer()

                            Text("Filter:")
                                .foregroundColor(.secondary)

                            Menu(searchDuration?.name ?? "Duration") {
                                Button("All") {
                                    searchDuration = nil
                                }
                                ForEach(SearchQuery.Duration.allCases) { duration in
                                    Button(duration.name) {
                                        searchDuration = duration
                                    }
                                }
                            }
                            .foregroundColor(searchDuration.isNil ? .secondary : .accentColor)

                            Menu(searchDate?.name ?? "Date") {
                                Button("All") {
                                    searchDate = nil
                                }
                                ForEach(SearchQuery.Date.allCases) { date in
                                    Button(date.name) {
                                        searchDate = date
                                    }
                                }
                            }
                            .foregroundColor(searchDate.isNil ? .secondary : .accentColor)
                        }
                    }
                    .transaction { t in t.animation = .none }
                }
            #endif
        }
        .onAppear {
            if query != nil {
                state.queryText = query!.query
                state.resetQuery(query!)
            }
        }
        .searchable(text: $state.queryText, placement: searchFieldPlacement) {
            ForEach(state.querySuggestions.collection, id: \.self) { suggestion in
                Text(suggestion)
                    .searchCompletion(suggestion)
            }
        }
        .onChange(of: state.queryText) { query in
            state.loadSuggestions(query)
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

    var recentQueries: some View {
        List {
            Section(header: Text("Recents")) {
                ForEach(recentItems) { item in
                    Button(item.title) {
                        state.queryText = item.title
                        state.changeQuery { query in query.query = item.title }
                    }
                    #if os(iOS)
                        .swipeActions(edge: .trailing) {
                            clearButton(item)
                        }
                    #endif
                }
            }
            .redrawOn(change: recentsChanged)

            clearAllButton
        }
        #if os(iOS)
            .listStyle(.insetGrouped)
        #endif
    }

    func clearButton(_ item: RecentItem) -> some View {
        Button(role: .destructive) {
            recents.close(item)
            recentsChanged.toggle()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

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
        searchDate != nil || searchDuration != nil
    }

    var recentItems: [RecentItem] {
        Defaults[.recentlyOpened].filter { $0.type == .query }.reversed()
    }
}
