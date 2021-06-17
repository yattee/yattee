enum TrendingCategory: String, CaseIterable, Identifiable {
    case `default`, music, gaming, movies

    var id: TrendingCategory.RawValue {
        rawValue
    }

    var name: String {
        rawValue.capitalized
    }
}
