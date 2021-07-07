import Defaults
import Foundation

enum SearchSortOrder: String, CaseIterable, Identifiable, DefaultsSerializable {
    case relevance, rating, uploadDate, viewCount

    var id: SearchSortOrder.RawValue {
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
