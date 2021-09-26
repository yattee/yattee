import Defaults

extension Defaults.Keys {
    #if os(tvOS)
        static let layout = Key<ListingLayout>("listingLayout", default: .cells)
    #endif

    static let instances = Key<[Instance]>("instances", default: [])
    static let accounts = Key<[Instance.Account]>("accounts", default: [])
    static let defaultAccountID = Key<String?>("defaultAccountID")

    static let trendingCategory = Key<TrendingCategory>("trendingCategory", default: .default)
    static let trendingCountry = Key<Country>("trendingCountry", default: .us)

    static let selectedPlaylistID = Key<String?>("selectedPlaylistID")
    static let showingAddToPlaylist = Key<Bool>("showingAddToPlaylist", default: false)
    static let videoIDToAddToPlaylist = Key<String?>("videoIDToAddToPlaylist")

    static let recentlyOpened = Key<[RecentItem]>("recentlyOpened", default: [])
    static let quality = Key<Stream.ResolutionSetting>("quality", default: .hd720pFirstThenBest)
}

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
