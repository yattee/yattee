import Defaults
import Foundation

final class SearchQuery: ObservableObject {
    enum Date: String, CaseIterable, Identifiable {
        case any, hour, today, week, month, year

        var id: SearchQuery.Date.RawValue {
            rawValue
        }

        var name: String {
            rawValue.capitalized.localized()
        }
    }

    enum Duration: String, CaseIterable, Identifiable {
        case any, short, long

        var id: SearchQuery.Duration.RawValue {
            rawValue
        }

        var name: String {
            rawValue.capitalized.localized()
        }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case relevance, rating, uploadDate, viewCount

        var id: SearchQuery.SortOrder.RawValue {
            rawValue
        }

        var name: String {
            switch self {
            case .uploadDate:
                return "Date".localized()
            case .viewCount:
                return "Views".localized()
            default:
                return rawValue.capitalized.localized()
            }
        }

        var parameter: String {
            switch self {
            case .uploadDate:
                return "date"
            case .viewCount:
                return "views"
            default:
                return rawValue
            }
        }
    }

    @Published var query: String
    @Published var sortBy: SearchQuery.SortOrder = .relevance
    @Published var date: SearchQuery.Date? = .month
    @Published var duration: SearchQuery.Duration?

    init(query: String = "", sortBy: SearchQuery.SortOrder = .relevance, date: SearchQuery.Date? = nil, duration: SearchQuery.Duration? = nil) {
        self.query = query
        self.sortBy = sortBy
        self.date = date
        self.duration = duration
    }

    var isEmpty: Bool {
        query.isEmpty
    }
}
