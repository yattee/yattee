import Defaults

enum TrendingCategory: String, CaseIterable, Identifiable, Defaults.Serializable {
    case `default`, music, gaming, movies

    var id: TrendingCategory.RawValue {
        rawValue
    }

    var name: String {
        rawValue.capitalized
    }
}
