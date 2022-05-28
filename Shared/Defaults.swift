import Defaults
import Foundation
#if os(iOS)
    import UIKit
#endif

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

    static let enableReturnYouTubeDislike = Key<Bool>("enableReturnYouTubeDislike", default: false)

    static let favorites = Key<[FavoriteItem]>("favorites", default: [
        .init(section: .channel("UCE_M8A5yxnLfW0KghEeajjw", "Apple"))
    ])

    #if !os(tvOS)
        static let accountPickerDisplaysUsername = Key<Bool>("accountPickerDisplaysUsername", default: false)
    #endif
    #if os(iOS)
        static let lockPortraitWhenBrowsing = Key<Bool>("lockPortraitWhenBrowsing", default: UIDevice.current.userInterfaceIdiom == .phone)
    #endif
    static let channelOnThumbnail = Key<Bool>("channelOnThumbnail", default: true)
    static let timeOnThumbnail = Key<Bool>("timeOnThumbnail", default: true)
    static let roundedThumbnails = Key<Bool>("roundedThumbnails", default: true)

    static let activeBackend = Key<PlayerBackendType>("activeBackend", default: .mpv)
    static let quality = Key<ResolutionSetting>("quality", default: .best)
    static let playerSidebar = Key<PlayerSidebarSetting>("playerSidebar", default: PlayerSidebarSetting.defaultValue)
    static let playerInstanceID = Key<Instance.ID?>("playerInstance")
    static let showKeywords = Key<Bool>("showKeywords", default: false)
    static let showHistoryInPlayer = Key<Bool>("showHistoryInPlayer", default: false)
    static let commentsInstanceID = Key<Instance.ID?>("commentsInstance", default: kavinPipedInstanceID)
    #if !os(tvOS)
        static let commentsPlacement = Key<CommentsPlacement>("commentsPlacement", default: .separate)
    #endif
    static let pauseOnHidingPlayer = Key<Bool>("pauseOnHidingPlayer", default: true)

    static let closePiPOnNavigation = Key<Bool>("closePiPOnNavigation", default: false)
    static let closePiPOnOpeningPlayer = Key<Bool>("closePiPOnOpeningPlayer", default: false)
    #if !os(macOS)
        static let closePiPAndOpenPlayerOnEnteringForeground = Key<Bool>("closePiPAndOpenPlayerOnEnteringForeground", default: false)
    #endif

    static let recentlyOpened = Key<[RecentItem]>("recentlyOpened", default: [])

    static let queue = Key<[PlayerQueueItem]>("queue", default: [])
    static let lastPlayed = Key<PlayerQueueItem?>("lastPlayed")

    static let saveHistory = Key<Bool>("saveHistory", default: true)
    static let showWatchingProgress = Key<Bool>("showWatchingProgress", default: true)
    static let watchedThreshold = Key<Int>("watchedThreshold", default: 90)
    static let watchedVideoStyle = Key<WatchedVideoStyle>("watchedVideoStyle", default: .badge)
    static let watchedVideoBadgeColor = Key<WatchedVideoBadgeColor>("WatchedVideoBadgeColor", default: .red)
    static let watchedVideoPlayNowBehavior = Key<WatchedVideoPlayNowBehavior>("watchedVideoPlayNowBehavior", default: .continue)
    static let resetWatchedStatusOnPlaying = Key<Bool>("resetWatchedStatusOnPlaying", default: false)
    static let saveRecents = Key<Bool>("saveRecents", default: true)

    static let trendingCategory = Key<TrendingCategory>("trendingCategory", default: .default)
    static let trendingCountry = Key<Country>("trendingCountry", default: .us)

    static let visibleSections = Key<Set<VisibleSection>>("visibleSections", default: [.favorites, .subscriptions, .trending, .playlists])

    #if os(macOS)
        static let enableBetaChannel = Key<Bool>("enableBetaChannel", default: false)
    #endif

    #if os(iOS)
        static let honorSystemOrientationLock = Key<Bool>("honorSystemOrientationLock", default: true)
        static let enterFullscreenInLandscape = Key<Bool>("enterFullscreenInLandscape", default: UIDevice.current.userInterfaceIdiom == .phone)
        static let lockLandscapeOnRotation = Key<Bool>("lockLandscapeOnRotation", default: false)
        static let lockLandscapeWhenEnteringFullscreen = Key<Bool>("lockLandscapeWhenEnteringFullscreen", default: false)
    #endif
}

enum ResolutionSetting: String, CaseIterable, Defaults.Serializable {
    case best
    case hd4320p60
    case hd4320p
    case hd2160p60
    case hd2160p
    case hd1440p60
    case hd1440p
    case hd1080p60
    case hd1080p
    case hd720p60
    case hd720p
    case sd480p
    case sd360p
    case sd240p
    case sd144p

    var value: Stream.Resolution {
        switch self {
        case .best:
            return .hd4320p60
        default:
            return Stream.Resolution(rawValue: rawValue)!
        }
    }

    var description: String {
        switch self {
        case .best:
            return "Best available quality"
        case .hd4320p60:
            return "8K, 60fps"
        case .hd4320p:
            return "8K"
        case .hd2160p60:
            return "4K, 60fps"
        case .hd2160p:
            return "4K"
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

enum WatchedVideoStyle: String, Defaults.Serializable {
    case nothing, badge, decreasedOpacity, both
}

enum WatchedVideoBadgeColor: String, Defaults.Serializable {
    case colorSchemeBased, red, blue
}

enum WatchedVideoPlayNowBehavior: String, Defaults.Serializable {
    case `continue`, restart
}

#if !os(tvOS)
    enum CommentsPlacement: String, CaseIterable, Defaults.Serializable {
        case info, separate
    }
#endif
