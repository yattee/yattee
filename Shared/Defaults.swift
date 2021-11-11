import Defaults
import Foundation

extension Defaults.Keys {
    static let instances = Key<[Instance]>("instances", default: [
        .init(
            app: .piped,
            id: "default-piped-instance",
            name: "Kavin",
            apiURL: "https://pipedapi.kavin.rocks",
            frontendURL: "https://piped.kavin.rocks"
        )
    ])
    static let accounts = Key<[Account]>("accounts", default: [])
    static let lastAccountID = Key<Account.ID?>("lastAccountID")
    static let lastInstanceID = Key<Instance.ID?>("lastInstanceID")
    static let lastUsedPlaylistID = Key<Playlist.ID?>("lastPlaylistID")

    static let sponsorBlockInstance = Key<String>("sponsorBlockInstance", default: "https://sponsor.ajay.app")
    static let sponsorBlockCategories = Key<Set<String>>("sponsorBlockCategories", default: Set(SponsorBlockAPI.categories))

    static let favorites = Key<[FavoriteItem]>("favorites", default: [
        .init(section: .trending("US", "default")),
        .init(section: .channel("UC-lHJZR3Gqxm24_Vd_AJ5Yw", "PewDiePie")),
        .init(section: .searchQuery("Apple Pie Recipes", "", "", ""))
    ])

    static let channelOnThumbnail = Key<Bool>("channelOnThumbnail", default: true)
    static let timeOnThumbnail = Key<Bool>("timeOnThumbnail", default: true)

    static let quality = Key<ResolutionSetting>("quality", default: .best)
    static let playerSidebar = Key<PlayerSidebarSetting>("playerSidebar", default: PlayerSidebarSetting.defaultValue)
    static let playerInstanceID = Key<Instance.ID?>("playerInstance")
    static let showKeywords = Key<Bool>("showKeywords", default: false)

    static let recentlyOpened = Key<[RecentItem]>("recentlyOpened", default: [])

    static let queue = Key<[PlayerQueueItem]>("queue", default: [])
    static let history = Key<[PlayerQueueItem]>("history", default: [])
    static let lastPlayed = Key<PlayerQueueItem?>("lastPlayed")

    static let saveHistory = Key<Bool>("saveHistory", default: true)

    static let trendingCategory = Key<TrendingCategory>("trendingCategory", default: .default)
    static let trendingCountry = Key<Country>("trendingCountry", default: .us)

    #if os(iOS)
        static let tabNavigationSection = Key<TabNavigationSectionSetting>("tabNavigationSection", default: .trending)
    #endif
}

enum ResolutionSetting: String, CaseIterable, Defaults.Serializable {
    case best, hd720p, sd480p, sd360p, sd240p, sd144p

    var value: Stream.Resolution {
        switch self {
        case .best:
            return .hd720p
        default:
            return Stream.Resolution(rawValue: rawValue)!
        }
    }

    var description: String {
        switch self {
        case .best:
            return "Best available"
        default:
            return value.name
        }
    }
}

enum PlayerSidebarSetting: String, CaseIterable, Defaults.Serializable {
    case always, whenFits, never

    static var defaultValue: Self {
        #if os(macOS)
            .always
        #else
            .whenFits
        #endif
    }
}

#if os(iOS)
    enum TabNavigationSectionSetting: String, Defaults.Serializable {
        case trending, popular
    }
#endif
