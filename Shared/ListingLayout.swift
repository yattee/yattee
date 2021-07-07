import Defaults

enum ListingLayout: String, CaseIterable, Identifiable, Defaults.Serializable {
    case list, cells

    var id: String {
        rawValue
    }

    var name: String {
        switch self {
        case .list:
            return "List"
        case .cells:
            return "Cells"
        }
    }
}
