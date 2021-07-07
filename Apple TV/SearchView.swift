import Defaults
import Siesta
import SwiftUI

struct SearchView: View {
    @Default(.searchQuery) private var queryText
    @Default(.searchSortOrder) private var searchSortOrder
    @Default(.searchDate) private var searchDate
    @Default(.searchDuration) private var searchDuration

    @ObservedObject private var store = Store<[Video]>()
    @ObservedObject private var query = SearchQuery()

    var body: some View {
        VStack {
            if !store.collection.isEmpty {
                VideosView(videos: store.collection)
            }

            if store.collection.isEmpty && !resource.isLoading {
                Text("No results")

                if searchFiltersActive {
                    Button("Reset search filters") {
                        Defaults.reset(.searchDate, .searchDuration)
                    }
                }

                Spacer()
            }
        }
        .searchable(text: $queryText)
        .onAppear {
            changeQuery {
                query.query = queryText
                query.sortBy = searchSortOrder
                query.date = searchDate
                query.duration = searchDuration
            }
        }
        .onChange(of: queryText) { queryText in
            changeQuery { query.query = queryText }
        }
        .onChange(of: searchSortOrder) { order in
            changeQuery { query.sortBy = order }
        }
        .onChange(of: searchDate) { date in
            changeQuery { query.date = date }
        }
        .onChange(of: searchDuration) { duration in
            changeQuery { query.duration = duration }
        }
    }

    func changeQuery(_ change: @escaping () -> Void = {}) {
        resource.removeObservers(ownedBy: store)
        change()

        resource.addObserver(store)
        resource.loadIfNeeded()
    }

    var resource: Resource {
        InvidiousAPI.shared.search(query)
    }

    var searchFiltersActive: Bool {
        searchDate != nil || searchDuration != nil
    }
}
