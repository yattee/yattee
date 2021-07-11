import Foundation

final class SearchQuery: ObservableObject {
    @Published var query: String
    @Published var sortBy: SearchSortOrder = .relevance
    @Published var date: SearchDate? = .month
    @Published var duration: SearchDuration?

    @Published var page = 1

    init(query: String = "", page: Int = 1, sortBy: SearchSortOrder = .relevance, date: SearchDate? = nil, duration: SearchDuration? = nil) {
        self.query = query
        self.page = page
        self.sortBy = sortBy
        self.date = date
        self.duration = duration
    }

    var isEmpty: Bool {
        query.isEmpty
    }
}
