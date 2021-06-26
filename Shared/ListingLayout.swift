import Defaults

enum ListingLayout: String, CaseIterable, Defaults.Serializable {
    case list, cells

    var name: String {
        switch self {
        case .list:
            return "List"
        case .cells:
            return "Cells"
        }
    }
}
