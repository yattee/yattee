import Defaults
import Foundation

final class SearchQuery: ObservableObject {
    enum Date: String, CaseIterable, Identifiable, DefaultsSerializable {
        case hour, today, week, month, year

        var id: SearchQuery.Date.RawValue {
            rawValue
        }

        var name: String {
            rawValue.capitalized
        }
    }

    enum Duration: String, CaseIterable, Identifiable, DefaultsSerializable {
        case short, long

        var id: SearchQuery.Duration.RawValue {
            rawValue
        }

        var name: String {
            rawValue.capitalized
        }
    }

    enum SortOrder: String, CaseIterable, Identifiable, DefaultsSerializable {
        case relevance, rating, uploadDate, viewCount

        var id: SearchQuery.SortOrder.RawValue {
            rawValue
        }

        var name: String {
            switch self {
            case .uploadDate:
                return "Upload Date"
            case .viewCount:
                return "View Count"
            default:
                return rawValue.capitalized
            }
        }

        var parameter: String {
            switch self {
            case .uploadDate:
                return "upload_date"
            case .viewCount:
                return "view_count"
            default:
                return rawValue
            }
        }
    }

    @Published var query: String
    @Published var sortBy: SearchQuery.SortOrder = .relevance
    @Published var date: SearchQuery.Date? = .month
    @Published var duration: SearchQuery.Duration?

    @Published var page = 1

    init(query: String = "", page: Int = 1, sortBy: SearchQuery.SortOrder = .relevance, date: SearchQuery.Date? = nil, duration: SearchQuery.Duration? = nil) {
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
