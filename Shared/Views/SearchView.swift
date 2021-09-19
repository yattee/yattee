import Defaults
import Siesta
import SwiftUI

struct SearchView: View {
    @Default(.searchSortOrder) private var searchSortOrder
    @Default(.searchDate) private var searchDate
    @Default(.searchDuration) private var searchDuration

    @EnvironmentObject<SearchState> private var state

    private var query: SearchQuery?

    init(_ query: SearchQuery? = nil) {
        self.query = query
    }

    var body: some View {
        VStack {
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
        .onAppear {
            if query != nil {
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

    var navigationTitle: String {
        state.query.query.isEmpty ? "Search" : "Search: \"\(state.query.query)\""
    }

    var searchFiltersActive: Bool {
        searchDate != nil || searchDuration != nil
    }
}
