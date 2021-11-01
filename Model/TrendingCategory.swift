import Defaults

enum TrendingCategory: String, CaseIterable, Identifiable, Defaults.Serializable {
    case `default`, music, gaming, movies

    var id: RawValue {
        rawValue
    }

    var title: RawValue {
        rawValue.capitalized
    }

    var name: String {
        id == "default" ? "Trending" : title
    }

    var controlLabel: String {
        id == "default" ? "All" : title
    }
}
