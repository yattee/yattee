import Defaults
import Foundation
import SwiftUI
#if os(iOS)
    import UIKit
#endif

extension Defaults.Keys {
    static let instancesManifest = Key<String>("instancesManifest", default: "")
    static let countryOfPublicInstances = Key<String?>("countryOfPublicInstances")

    static let instances = Key<[Instance]>("instances", default: [])
    static let accounts = Key<[Account]>("accounts", default: [])
    static let lastAccountID = Key<Account.ID?>("lastAccountID")
    static let lastInstanceID = Key<Instance.ID?>("lastInstanceID")
    static let lastUsedPlaylistID = Key<Playlist.ID?>("lastPlaylistID")
    static let lastAccountIsPublic = Key<Bool>("lastAccountIsPublic", default: false)

    static let sponsorBlockInstance = Key<String>("sponsorBlockInstance", default: "https://sponsor.ajay.app")
    static let sponsorBlockCategories = Key<Set<String>>("sponsorBlockCategories", default: Set(SponsorBlockAPI.categories))

    static let enableReturnYouTubeDislike = Key<Bool>("enableReturnYouTubeDislike", default: false)

    static let showHome = Key<Bool>("showHome", default: true)
    static let showDocuments = Key<Bool>("showDocuments", default: true)
    static let showOpenActionsInHome = Key<Bool>("showOpenActionsInHome", default: true)
    static let showOpenActionsToolbarItem = Key<Bool>("showOpenActionsToolbarItem", default: false)
    static let showFavoritesInHome = Key<Bool>("showFavoritesInHome", default: true)
    static let homeHistoryItems = Key<Int>("homeHistoryItems", default: 10)
    static let favorites = Key<[FavoriteItem]>("favorites", default: [])

    #if !os(tvOS)
        #if os(macOS)
            static let accountPickerDisplaysUsernameDefault = true
        #else
            static let accountPickerDisplaysUsernameDefault = UIDevice.current.userInterfaceIdiom == .pad
        #endif
        static let accountPickerDisplaysUsername = Key<Bool>("accountPickerDisplaysUsername", default: accountPickerDisplaysUsernameDefault)
    #endif
    static let accountPickerDisplaysAnonymousAccounts = Key<Bool>("accountPickerDisplaysAnonymousAccounts", default: true)
    #if os(iOS)
        static let lockPortraitWhenBrowsing = Key<Bool>("lockPortraitWhenBrowsing", default: UIDevice.current.userInterfaceIdiom == .phone)
    #endif
    static let channelOnThumbnail = Key<Bool>("channelOnThumbnail", default: true)
    static let timeOnThumbnail = Key<Bool>("timeOnThumbnail", default: true)
    static let roundedThumbnails = Key<Bool>("roundedThumbnails", default: true)
    static let thumbnailsQuality = Key<ThumbnailsQuality>("thumbnailsQuality", default: .highest)

    static let captionsLanguageCode = Key<String?>("captionsLanguageCode")
    static let activeBackend = Key<PlayerBackendType>("activeBackend", default: .mpv)

    static let hd2160pMPVProfile = QualityProfile(id: "hd2160pMPVProfile", backend: .mpv, resolution: .hd2160p60, formats: QualityProfile.Format.allCases)
    static let hd1080pMPVProfile = QualityProfile(id: "hd1080pMPVProfile", backend: .mpv, resolution: .hd1080p60, formats: QualityProfile.Format.allCases)
    static let hd720pMPVProfile = QualityProfile(id: "hd720pMPVProfile", backend: .mpv, resolution: .hd720p60, formats: QualityProfile.Format.allCases)
    static let hd720pAVPlayerProfile = QualityProfile(id: "hd720pAVPlayerProfile", backend: .appleAVPlayer, resolution: .hd720p60, formats: [.hls, .stream])
    static let sd360pAVPlayerProfile = QualityProfile(id: "sd360pAVPlayerProfile", backend: .appleAVPlayer, resolution: .sd360p30, formats: [.hls, .stream])

    #if os(iOS)
        static let qualityProfilesDefault = UIDevice.current.userInterfaceIdiom == .pad ? [
            hd2160pMPVProfile,
            hd1080pMPVProfile,
            hd720pAVPlayerProfile,
            sd360pAVPlayerProfile
        ] : [
            hd1080pMPVProfile,
            hd720pAVPlayerProfile,
            sd360pAVPlayerProfile
        ]

        static let batteryCellularProfileDefault = hd720pAVPlayerProfile.id
        static let batteryNonCellularProfileDefault = hd720pAVPlayerProfile.id
        static let chargingCellularProfileDefault = hd720pAVPlayerProfile.id
        static let chargingNonCellularProfileDefault = hd1080pMPVProfile.id
    #elseif os(tvOS)
        static let qualityProfilesDefault = [
            hd2160pMPVProfile,
            hd1080pMPVProfile,
            hd720pAVPlayerProfile
        ]
        static let batteryCellularProfileDefault = hd1080pMPVProfile.id
        static let batteryNonCellularProfileDefault = hd1080pMPVProfile.id
        static let chargingCellularProfileDefault = hd1080pMPVProfile.id
        static let chargingNonCellularProfileDefault = hd1080pMPVProfile.id
    #else
        static let qualityProfilesDefault = [
            hd2160pMPVProfile,
            hd1080pMPVProfile,
            hd720pAVPlayerProfile
        ]
        static let batteryCellularProfileDefault = hd1080pMPVProfile.id
        static let batteryNonCellularProfileDefault = hd1080pMPVProfile.id
        static let chargingCellularProfileDefault = hd1080pMPVProfile.id
        static let chargingNonCellularProfileDefault = hd1080pMPVProfile.id
    #endif
    static let playerRate = Key<Double>("playerRate", default: 1.0)
    static let qualityProfiles = Key<[QualityProfile]>("qualityProfiles", default: qualityProfilesDefault)
    static let batteryCellularProfile = Key<QualityProfile.ID>("batteryCellularProfile", default: batteryCellularProfileDefault)
    static let batteryNonCellularProfile = Key<QualityProfile.ID>("batteryNonCellularProfile", default: batteryNonCellularProfileDefault)
    static let chargingCellularProfile = Key<QualityProfile.ID>("chargingCellularProfile", default: chargingCellularProfileDefault)
    static let chargingNonCellularProfile = Key<QualityProfile.ID>("chargingNonCellularProfile", default: chargingNonCellularProfileDefault)
    static let forceAVPlayerForLiveStreams = Key<Bool>("forceAVPlayerForLiveStreams", default: true)

    static let playerSidebar = Key<PlayerSidebarSetting>("playerSidebar", default: PlayerSidebarSetting.defaultValue)
    static let playerInstanceID = Key<Instance.ID?>("playerInstance")

    #if os(iOS)
        static let playerControlsLayoutDefault = UIDevice.current.userInterfaceIdiom == .pad ? PlayerControlsLayout.medium : .small
        static let fullScreenPlayerControlsLayoutDefault = UIDevice.current.userInterfaceIdiom == .pad ? PlayerControlsLayout.medium : .small
    #elseif os(tvOS)
        static let playerControlsLayoutDefault = PlayerControlsLayout.tvRegular
        static let fullScreenPlayerControlsLayoutDefault = PlayerControlsLayout.tvRegular
    #else
        static let playerControlsLayoutDefault = PlayerControlsLayout.medium
        static let fullScreenPlayerControlsLayoutDefault = PlayerControlsLayout.medium
    #endif

    static let playerControlsLayout = Key<PlayerControlsLayout>("playerControlsLayout", default: playerControlsLayoutDefault)
    static let fullScreenPlayerControlsLayout = Key<PlayerControlsLayout>("fullScreenPlayerControlsLayout", default: fullScreenPlayerControlsLayoutDefault)
    static let horizontalPlayerGestureEnabled = Key<Bool>("horizontalPlayerGestureEnabled", default: true)
    static let seekGestureSpeed = Key<Double>("seekGestureSpeed", default: 0.5)
    static let seekGestureSensitivity = Key<Double>("seekGestureSensitivity", default: 20.0)
    static let showKeywords = Key<Bool>("showKeywords", default: false)
    #if !os(tvOS)
        static let commentsPlacement = Key<CommentsPlacement>("commentsPlacement", default: .separate)
    #endif

    #if os(tvOS)
        static let pauseOnHidingPlayerDefault = true
    #else
        static let pauseOnHidingPlayerDefault = false
    #endif
    static let pauseOnHidingPlayer = Key<Bool>("pauseOnHidingPlayer", default: pauseOnHidingPlayerDefault)

    #if !os(macOS)
        static let pauseOnEnteringBackground = Key<Bool>("pauseOnEnteringBackground", default: true)
    #endif
    #if os(tvOS)
        static let closeLastItemOnPlaybackEndDefault = true
    #else
        static let closeLastItemOnPlaybackEndDefault = false
    #endif
    static let closeLastItemOnPlaybackEnd = Key<Bool>("closeLastItemOnPlaybackEnd", default: closeLastItemOnPlaybackEndDefault)

    #if os(tvOS)
        static let closePlayerOnItemCloseDefault = true
    #else
        static let closePlayerOnItemCloseDefault = false
    #endif
    static let closePlayerOnItemClose = Key<Bool>("closePlayerOnItemClose", default: closePlayerOnItemCloseDefault)

    static let closePiPOnNavigation = Key<Bool>("closePiPOnNavigation", default: false)
    static let closePiPOnOpeningPlayer = Key<Bool>("closePiPOnOpeningPlayer", default: false)
    #if !os(macOS)
        static let closePiPAndOpenPlayerOnEnteringForeground = Key<Bool>("closePiPAndOpenPlayerOnEnteringForeground", default: false)
    #endif
    static let closePlayerOnOpeningPiP = Key<Bool>("closePlayerOnOpeningPiP", default: false)

    static let recentlyOpened = Key<[RecentItem]>("recentlyOpened", default: [])

    static let queue = Key<[PlayerQueueItem]>("queue", default: [])
    static let saveLastPlayed = Key<Bool>("saveLastPlayed", default: false)
    static let lastPlayed = Key<PlayerQueueItem?>("lastPlayed")
    static let playbackMode = Key<PlayerModel.PlaybackMode>("playbackMode", default: .queue)

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

    static let visibleSections = Key<Set<VisibleSection>>("visibleSections", default: [.subscriptions, .trending, .playlists])

    #if os(iOS)
        static let enterFullscreenInLandscape = Key<Bool>("enterFullscreenInLandscape", default: UIDevice.current.userInterfaceIdiom == .phone)
        static let rotateToPortraitOnExitFullScreen = Key<Bool>("rotateToPortraitOnExitFullScreen", default: UIDevice.current.userInterfaceIdiom == .phone)
    #endif

    static let showMPVPlaybackStats = Key<Bool>("showMPVPlaybackStats", default: false)

    #if os(macOS)
        static let playerDetailsPageButtonLabelStyleDefault = PlayerDetailsPageButtonLabelStyle.iconAndText
    #else
        static let playerDetailsPageButtonLabelStyleDefault = UIDevice.current.userInterfaceIdiom == .phone ? PlayerDetailsPageButtonLabelStyle.iconOnly : .iconAndText
    #endif
    static let playerDetailsPageButtonLabelStyle = Key<PlayerDetailsPageButtonLabelStyle>("playerDetailsPageButtonLabelStyle", default: playerDetailsPageButtonLabelStyleDefault)

    static let systemControlsCommands = Key<SystemControlsCommands>("systemControlsCommands", default: .restartAndAdvanceToNext)
    static let mpvCacheSecs = Key<String>("mpvCacheSecs", default: "120")
    static let mpvCachePauseWait = Key<String>("mpvCachePauseWait", default: "3")
    static let mpvEnableLogging = Key<Bool>("mpvEnableLogging", default: false)
}

enum ResolutionSetting: String, CaseIterable, Defaults.Serializable {
    case hd2160p60
    case hd2160p30
    case hd1440p60
    case hd1440p30
    case hd1080p60
    case hd1080p30
    case hd720p60
    case hd720p30
    case sd480p30
    case sd360p30
    case sd240p30
    case sd144p30

    var value: Stream.Resolution! {
        .init(rawValue: rawValue)
    }

    var description: String {
        switch self {
        case .hd2160p60:
            return "4K, 60fps"
        case .hd2160p30:
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
    case subscriptions, popular, trending, playlists

    var title: String {
        rawValue.capitalized.localized()
    }

    var tabSelection: TabSelection {
        switch self {
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
        case .subscriptions:
            return 0
        case .popular:
            return 1
        case .trending:
            return 2
        case .playlists:
            return 3
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

enum WatchedVideoStyle: String, Defaults.Serializable {
    case nothing, badge, decreasedOpacity, both

    var isShowingBadge: Bool {
        self == .badge || self == .both
    }

    var isDecreasingOpacity: Bool {
        self == .decreasedOpacity || self == .both
    }
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

enum PlayerDetailsPageButtonLabelStyle: String, CaseIterable, Defaults.Serializable {
    case iconOnly, iconAndText

    var text: Bool {
        self == .iconAndText
    }
}

enum ThumbnailsQuality: String, CaseIterable, Defaults.Serializable {
    case highest, medium, low

    var description: String {
        switch self {
        case .highest:
            return "Highest quality".localized()
        case .medium:
            return "Medium quality".localized()
        case .low:
            return "Low quality".localized()
        }
    }
}

enum SystemControlsCommands: String, CaseIterable, Defaults.Serializable {
    case seek, restartAndAdvanceToNext
}
