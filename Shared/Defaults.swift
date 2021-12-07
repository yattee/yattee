import Defaults
import Foundation

extension Defaults.Keys {
    static let kavinPipedInstanceID = "kavin-piped"
    static let instances = Key<[Instance]>("instances", default: [
        .init(
            app: .piped,
            id: kavinPipedInstanceID,
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
    static let commentsInstanceID = Key<Instance.ID?>("commentsInstance", default: kavinPipedInstanceID)
    #if !os(tvOS)
        static let commentsPlacement = Key<CommentsPlacement>("commentsPlacement", default: .separate)
    #endif

    static let recentlyOpened = Key<[RecentItem]>("recentlyOpened", default: [])

    static let queue = Key<[PlayerQueueItem]>("queue", default: [])
    static let history = Key<[PlayerQueueItem]>("history", default: [])
    static let lastPlayed = Key<PlayerQueueItem?>("lastPlayed")

    static let saveHistory = Key<Bool>("saveHistory", default: true)
    static let saveRecents = Key<Bool>("saveRecents", default: true)

    static let trendingCategory = Key<TrendingCategory>("trendingCategory", default: .default)
    static let trendingCountry = Key<Country>("trendingCountry", default: .us)

    static let visibleSections = Key<Set<VisibleSection>>("visibleSections", default: [.favorites, .subscriptions, .trending, .playlists])

    #if os(macOS)
        static let enableBetaChannel = Key<Bool>("enableBetaChannel", default: false)
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

enum VisibleSection: String, CaseIterable, Comparable, Defaults.Serializable {
    case favorites, subscriptions, popular, trending, playlists

    static func from(_ string: String) -> VisibleSection {
        allCases.first { $0.rawValue == string }!
    }

    var title: String {
        rawValue.localizedCapitalized
    }

    var tabSelection: TabSelection {
        switch self {
        case .favorites:
            return TabSelection.favorites
        case .subscriptions:
            return TabSelection.subscriptions
        case .popular:
            return TabSelection.popular
        case .trending:
            return TabSelection.trending
        case .playlists:
            return TabSelection.playlists
        }
    }

    private var sortOrder: Int {
        switch self {
        case .favorites:
            return 0
        case .subscriptions:
            return 1
        case .popular:
            return 2
        case .trending:
            return 3
        case .playlists:
            return 4
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

#if !os(tvOS)
    enum CommentsPlacement: String, CaseIterable, Defaults.Serializable {
        case info, separate
    }
#endif
