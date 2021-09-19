import Defaults
import Siesta
import SwiftUI

struct SearchView: View {
    @Default(.searchSortOrder) private var searchSortOrder
    @Default(.searchDate) private var searchDate
    @Default(.searchDuration) private var searchDuration

    @EnvironmentObject<Recents> private var recents
    @EnvironmentObject<SearchState> private var state

    @Environment(\.navigationStyle) private var navigationStyle

    @State private var presentingClearConfirmation = false
    @State private var recentsChanged = false

    private var query: SearchQuery?

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
                            Defaults.reset(.searchDate, .searchDuration)
                        }
                    }

                    Spacer()
                }
            }
        }
        .onAppear {
            if query != nil {
                if navigationStyle == .tab {
                    state.queryText = query!.query
                }
                state.resetQuery(query!)
            }
        }
        .onChange(of: state.query.query) { queryText in
            state.changeQuery { query in query.query = queryText }
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
            .navigationTitle(navigationTitle)
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
            .opacity(recentsChanged ? 1 : 1)

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

    var navigationTitle: String {
        if state.query.query.isEmpty || (navigationStyle == .tab && state.queryText.isEmpty) {
            return "Search"
        }

        return "Search: \"\(state.query.query)\""
    }

    var searchFiltersActive: Bool {
        searchDate != nil || searchDuration != nil
    }

    var recentItems: [RecentItem] {
        Defaults[.recentlyOpened].filter { $0.type == .query }.reversed()
    }
}
