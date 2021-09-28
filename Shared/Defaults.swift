import Defaults

extension Defaults.Keys {
    static let instances = Key<[Instance]>("instances", default: [])
    static let accounts = Key<[Instance.Account]>("accounts", default: [])
    static let defaultAccountID = Key<String?>("defaultAccountID")

    static let quality = Key<Stream.ResolutionSetting>("quality", default: .hd720pFirstThenBest)

    static let recentlyOpened = Key<[RecentItem]>("recentlyOpened", default: [])

    static let trendingCategory = Key<TrendingCategory>("trendingCategory", default: .default)
    static let trendingCountry = Key<Country>("trendingCountry", default: .us)
}
