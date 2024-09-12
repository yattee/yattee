import Defaults
import Foundation
import SwiftUI
#if os(iOS)
    import UIKit
#endif

extension Defaults.Keys {
    // MARK: GROUP - Browsing

    static let showHome = Key<Bool>("showHome", default: true)
    static let showOpenActionsInHome = Key<Bool>("showOpenActionsInHome", default: true)
    static let showQueueInHome = Key<Bool>("showQueueInHome", default: true)
    static let showFavoritesInHome = Key<Bool>("showFavoritesInHome", default: true)
    static let favorites = Key<[FavoriteItem]>("favorites", default: [])
    static let widgetsSettings = Key<[WidgetSettings]>("widgetsSettings", default: [])
    static let startupSection = Key<StartupSection>("startupSection", default: .home)
    static let showSearchSuggestions = Key<Bool>("showSearchSuggestions", default: true)
    static let visibleSections = Key<Set<VisibleSection>>("visibleSections", default: [.subscriptions, .trending, .playlists])

    static let showOpenActionsToolbarItem = Key<Bool>("showOpenActionsToolbarItem", default: false)
    #if os(iOS)
        static let showDocuments = Key<Bool>("showDocuments", default: false)
        static let lockPortraitWhenBrowsing = Key<Bool>("lockPortraitWhenBrowsing", default: Constants.isIPhone)
    #endif

    #if !os(tvOS)
        #if os(macOS)
            static let accountPickerDisplaysUsernameDefault = true
        #else
            static let accountPickerDisplaysUsernameDefault = Constants.isIPad
        #endif
        static let accountPickerDisplaysUsername = Key<Bool>("accountPickerDisplaysUsername", default: accountPickerDisplaysUsernameDefault)
    #endif

    static let accountPickerDisplaysAnonymousAccounts = Key<Bool>("accountPickerDisplaysAnonymousAccounts", default: true)
    static let showUnwatchedFeedBadges = Key<Bool>("showUnwatchedFeedBadges", default: false)
    static let expandChannelDescription = Key<Bool>("expandChannelDescription", default: false)

    static let keepChannelsWithUnwatchedFeedOnTop = Key<Bool>("keepChannelsWithUnwatchedFeedOnTop", default: true)
    static let showChannelAvatarInChannelsLists = Key<Bool>("showChannelAvatarInChannelsLists", default: true)
    static let showChannelAvatarInVideosListing = Key<Bool>("showChannelAvatarInVideosListing", default: true)

    static let playerButtonSingleTapGesture = Key<PlayerTapGestureAction>("playerButtonSingleTapGesture", default: .togglePlayer)
    static let playerButtonDoubleTapGesture = Key<PlayerTapGestureAction>("playerButtonDoubleTapGesture", default: .togglePlayerVisibility)
    static let playerButtonShowsControlButtonsWhenMinimized = Key<Bool>("playerButtonShowsControlButtonsWhenMinimized", default: true)
    static let playerButtonIsExpanded = Key<Bool>("playerButtonIsExpanded", default: true)
    static let playerBarMaxWidth = Key<String>("playerBarMaxWidth", default: "600")
    static let channelOnThumbnail = Key<Bool>("channelOnThumbnail", default: false)
    static let timeOnThumbnail = Key<Bool>("timeOnThumbnail", default: true)
    static let roundedThumbnails = Key<Bool>("roundedThumbnails", default: true)
    static let thumbnailsQuality = Key<ThumbnailsQuality>("thumbnailsQuality", default: .highest)

    // MARK: GROUP - Player

    static let playerInstanceID = Key<Instance.ID?>("playerInstance")

    #if os(tvOS)
        static let pauseOnHidingPlayerDefault = true
    #else
        static let pauseOnHidingPlayerDefault = false
    #endif
    static let pauseOnHidingPlayer = Key<Bool>("pauseOnHidingPlayer", default: pauseOnHidingPlayerDefault)

    static let closeVideoOnEOF = Key<Bool>("closeVideoOnEOF", default: false)

    #if !os(macOS)
        static let pauseOnEnteringBackground = Key<Bool>("pauseOnEnteringBackground", default: false)
    #endif

    #if os(iOS)
        static let expandVideoDescriptionDefault = Constants.isIPad
    #else
        static let expandVideoDescriptionDefault = true
    #endif
    static let expandVideoDescription = Key<Bool>("expandVideoDescription", default: expandVideoDescriptionDefault)

    static let collapsedLinesDescription = Key<Int>("collapsedLinesDescription", default: 5)
    static let exitFullscreenOnEOF = Key<Bool>("exitFullscreenOnEOF", default: true)

    static let showChapters = Key<Bool>("showChapters", default: true)
    static let showChapterThumbnails = Key<Bool>("showChapterThumbnails", default: true)
    static let showChapterThumbnailsOnlyWhenDifferent = Key<Bool>("showChapterThumbnailsOnlyWhenDifferent", default: false)
    static let expandChapters = Key<Bool>("expandChapters", default: true)
    static let showRelated = Key<Bool>("showRelated", default: true)
    static let showInspector = Key<ShowInspectorSetting>("showInspector", default: .onlyLocal)

    static let playerSidebar = Key<PlayerSidebarSetting>("playerSidebar", default: .defaultValue)
    static let showKeywords = Key<Bool>("showKeywords", default: false)
    static let showComments = Key<Bool>("showComments", default: true)
    #if !os(tvOS)
        static let showScrollToTopInComments = Key<Bool>("showScrollToTopInComments", default: true)
    #endif
    static let enableReturnYouTubeDislike = Key<Bool>("enableReturnYouTubeDislike", default: false)

    #if os(iOS)
        static let isOrientationLocked = Key<Bool>("isOrientationLocked", default: Constants.isIPhone)
        static let enterFullscreenInLandscape = Key<Bool>("enterFullscreenInLandscape", default: Constants.isIPhone)
        static let rotateToLandscapeOnEnterFullScreen = Key<FullScreenRotationSetting>("rotateToLandscapeOnEnterFullScreen", default: .landscapeRight)
    #endif

    static let closePiPOnNavigation = Key<Bool>("closePiPOnNavigation", default: false)
    static let closePiPOnOpeningPlayer = Key<Bool>("closePiPOnOpeningPlayer", default: false)
    static let closePlayerOnOpeningPiP = Key<Bool>("closePlayerOnOpeningPiP", default: false)
    #if !os(macOS)
        static let closePiPAndOpenPlayerOnEnteringForeground = Key<Bool>("closePiPAndOpenPlayerOnEnteringForeground", default: false)
    #endif

    static let captionsAutoShow = Key<Bool>("captionsAutoShow", default: false)
    static let captionsDefaultLanguageCode = Key<String>("captionsDefaultLanguageCode", default: LanguageCodes.English.rawValue)
    static let captionsFallbackLanguageCode = Key<String>("captionsDefaultFallbackCode", default: LanguageCodes.English.rawValue)
    static let captionsFontScaleSize = Key<String>("captionsFontScale", default: "1.0")
    static let captionsFontColor = Key<String>("captionsFontColor", default: "#FFFFFF")

    // MARK: GROUP - Controls

    static let avPlayerUsesSystemControls = Key<Bool>("avPlayerUsesSystemControls", default: Constants.isTvOS)
    static let horizontalPlayerGestureEnabled = Key<Bool>("horizontalPlayerGestureEnabled", default: true)
    static let fullscreenPlayerGestureEnabled = Key<Bool>("fullscreenPlayerGestureEnabled", default: true)
    static let seekGestureSensitivity = Key<Double>("seekGestureSensitivity", default: 30.0)
    static let seekGestureSpeed = Key<Double>("seekGestureSpeed", default: 0.5)

    #if os(iOS)
        static let playerControlsLayoutDefault = Constants.isIPad ? PlayerControlsLayout.medium : .small
        static let fullScreenPlayerControlsLayoutDefault = Constants.isIPad ? PlayerControlsLayout.medium : .small
    #elseif os(tvOS)
        static let playerControlsLayoutDefault = PlayerControlsLayout.tvRegular
        static let fullScreenPlayerControlsLayoutDefault = PlayerControlsLayout.tvRegular
    #else
        static let playerControlsLayoutDefault = PlayerControlsLayout.medium
        static let fullScreenPlayerControlsLayoutDefault = PlayerControlsLayout.medium
    #endif

    static let playerControlsLayout = Key<PlayerControlsLayout>("playerControlsLayout", default: playerControlsLayoutDefault)
    static let fullScreenPlayerControlsLayout = Key<PlayerControlsLayout>("fullScreenPlayerControlsLayout", default: fullScreenPlayerControlsLayoutDefault)
    static let playerControlsBackgroundOpacity = Key<Double>("playerControlsBackgroundOpacity", default: 0.2)

    static let systemControlsCommands = Key<SystemControlsCommands>("systemControlsCommands", default: .restartAndAdvanceToNext)

    static let buttonBackwardSeekDuration = Key<String>("buttonBackwardSeekDuration", default: "10")
    static let buttonForwardSeekDuration = Key<String>("buttonForwardSeekDuration", default: "10")
    static let gestureBackwardSeekDuration = Key<String>("gestureBackwardSeekDuration", default: "10")
    static let gestureForwardSeekDuration = Key<String>("gestureForwardSeekDuration", default: "10")
    static let systemControlsSeekDuration = Key<String>("systemControlsBackwardSeekDuration", default: "10")

    #if os(iOS)
        static let playerControlsLockOrientationEnabled = Key<Bool>("playerControlsLockOrientationEnabled", default: true)
    #endif
    #if os(tvOS)
        static let playerControlsSettingsEnabledDefault = true
    #else
        static let playerControlsSettingsEnabledDefault = false
    #endif
    static let playerControlsSettingsEnabled = Key<Bool>("playerControlsSettingsEnabled", default: playerControlsSettingsEnabledDefault)
    static let playerControlsCloseEnabled = Key<Bool>("playerControlsCloseEnabled", default: true)
    static let playerControlsRestartEnabled = Key<Bool>("playerControlsRestartEnabled", default: false)
    static let playerControlsAdvanceToNextEnabled = Key<Bool>("playerControlsAdvanceToNextEnabled", default: false)
    static let playerControlsPlaybackModeEnabled = Key<Bool>("playerControlsPlaybackModeEnabled", default: false)
    static let playerControlsMusicModeEnabled = Key<Bool>("playerControlsMusicModeEnabled", default: false)

    static let playerActionsButtonLabelStyle = Key<ButtonLabelStyle>("playerActionsButtonLabelStyle", default: .iconAndText)

    static let actionButtonShareEnabled = Key<Bool>("actionButtonShareEnabled", default: true)
    static let actionButtonAddToPlaylistEnabled = Key<Bool>("actionButtonAddToPlaylistEnabled", default: true)
    static let actionButtonSubscribeEnabled = Key<Bool>("actionButtonSubscribeEnabled", default: false)
    static let actionButtonSettingsEnabled = Key<Bool>("actionButtonSettingsEnabled", default: true)
    static let actionButtonHideEnabled = Key<Bool>("actionButtonHideEnabled", default: false)
    static let actionButtonCloseEnabled = Key<Bool>("actionButtonCloseEnabled", default: true)
    static let actionButtonFullScreenEnabled = Key<Bool>("actionButtonFullScreenEnabled", default: false)
    static let actionButtonPipEnabled = Key<Bool>("actionButtonPipEnabled", default: false)
    static let actionButtonLockOrientationEnabled = Key<Bool>("actionButtonLockOrientationEnabled", default: false)
    static let actionButtonRestartEnabled = Key<Bool>("actionButtonRestartEnabled", default: false)
    static let actionButtonAdvanceToNextItemEnabled = Key<Bool>("actionButtonAdvanceToNextItemEnabled", default: false)
    static let actionButtonMusicModeEnabled = Key<Bool>("actionButtonMusicModeEnabled", default: true)

    // MARK: GROUP - Quality

    static let hd2160p60MPVProfile = QualityProfile(id: "hd2160p60MPVProfile", backend: .mpv, resolution: .hd2160p60, formats: QualityProfile.Format.allCases, order: Array(QualityProfile.Format.allCases.indices))
    static let hd1080p60MPVProfile = QualityProfile(id: "hd1080p60MPVProfile", backend: .mpv, resolution: .hd1080p60, formats: QualityProfile.Format.allCases, order: Array(QualityProfile.Format.allCases.indices))
    static let hd1080pMPVProfile = QualityProfile(id: "hd1080pMPVProfile", backend: .mpv, resolution: .hd1080p30, formats: QualityProfile.Format.allCases, order: Array(QualityProfile.Format.allCases.indices))
    static let hd720p60MPVProfile = QualityProfile(id: "hd720p60MPVProfile", backend: .mpv, resolution: .hd720p60, formats: QualityProfile.Format.allCases, order: Array(QualityProfile.Format.allCases.indices))
    static let hd720pMPVProfile = QualityProfile(id: "hd720pMPVProfile", backend: .mpv, resolution: .hd720p30, formats: QualityProfile.Format.allCases, order: Array(QualityProfile.Format.allCases.indices))
    static let sd360pMPVProfile = QualityProfile(id: "sd360pMPVProfile", backend: .mpv, resolution: .sd360p30, formats: QualityProfile.Format.allCases, order: Array(QualityProfile.Format.allCases.indices))
    static let hd720pAVPlayerProfile = QualityProfile(id: "hd720pAVPlayerProfile", backend: .appleAVPlayer, resolution: .hd720p30, formats: [.stream, .hls], order: Array(QualityProfile.Format.allCases.indices))
    static let sd360pAVPlayerProfile = QualityProfile(id: "sd360pAVPlayerProfile", backend: .appleAVPlayer, resolution: .sd360p30, formats: [.stream, .hls], order: Array(QualityProfile.Format.allCases.indices))

    #if os(iOS)
        enum QualityProfiles {
            // iPad-specific settings
            enum iPad {
                static let qualityProfilesDefault = [
                    hd1080p60MPVProfile,
                    hd1080pMPVProfile,
                    hd720p60MPVProfile,
                    hd720pMPVProfile
                ]

                static let batteryCellularProfileDefault = hd720pMPVProfile.id
                static let batteryNonCellularProfileDefault = hd720p60MPVProfile.id
                static let chargingCellularProfileDefault = hd1080pMPVProfile.id
                static let chargingNonCellularProfileDefault = hd1080p60MPVProfile.id
            }

            // iPhone-specific settings
            enum iPhone {
                static let qualityProfilesDefault = [
                    hd1080p60MPVProfile,
                    hd1080pMPVProfile,
                    hd720p60MPVProfile,
                    hd720pMPVProfile,
                    sd360pMPVProfile
                ]

                static let batteryCellularProfileDefault = sd360pMPVProfile.id
                static let batteryNonCellularProfileDefault = hd720p60MPVProfile.id
                static let chargingCellularProfileDefault = hd720pMPVProfile.id
                static let chargingNonCellularProfileDefault = hd1080p60MPVProfile.id
            }

            // Access the correct profile based on device type
            static var currentProfile: (qualityProfilesDefault: [QualityProfile], batteryCellularProfileDefault: String, batteryNonCellularProfileDefault: String, chargingCellularProfileDefault: String, chargingNonCellularProfileDefault: String) {
                if Constants.isIPad {
                    return (
                        qualityProfilesDefault: iPad.qualityProfilesDefault,
                        batteryCellularProfileDefault: iPad.batteryCellularProfileDefault,
                        batteryNonCellularProfileDefault: iPad.batteryNonCellularProfileDefault,
                        chargingCellularProfileDefault: iPad.chargingCellularProfileDefault,
                        chargingNonCellularProfileDefault: iPad.chargingNonCellularProfileDefault
                    )
                }

                return (
                    qualityProfilesDefault: iPhone.qualityProfilesDefault,
                    batteryCellularProfileDefault: iPhone.batteryCellularProfileDefault,
                    batteryNonCellularProfileDefault: iPhone.batteryNonCellularProfileDefault,
                    chargingCellularProfileDefault: iPhone.chargingCellularProfileDefault,
                    chargingNonCellularProfileDefault: iPhone.chargingNonCellularProfileDefault
                )
            }
        }

    #elseif os(tvOS)
        enum QualityProfiles {
            // tvOS-specific settings
            enum tvOS {
                static let qualityProfilesDefault = [
                    hd2160p60MPVProfile,
                    hd1080p60MPVProfile,
                    hd720p60MPVProfile,
                    hd720pAVPlayerProfile
                ]

                static let batteryCellularProfileDefault = hd1080p60MPVProfile.id
                static let batteryNonCellularProfileDefault = hd1080p60MPVProfile.id
                static let chargingCellularProfileDefault = hd1080p60MPVProfile.id
                static let chargingNonCellularProfileDefault = hd1080p60MPVProfile.id
            }

            // Access the correct profile based on device type
            static var currentProfile: (qualityProfilesDefault: [QualityProfile], batteryCellularProfileDefault: String, batteryNonCellularProfileDefault: String, chargingCellularProfileDefault: String, chargingNonCellularProfileDefault: String) {
                (
                    qualityProfilesDefault: tvOS.qualityProfilesDefault,
                    batteryCellularProfileDefault: tvOS.batteryCellularProfileDefault,
                    batteryNonCellularProfileDefault: tvOS.batteryNonCellularProfileDefault,
                    chargingCellularProfileDefault: tvOS.chargingCellularProfileDefault,
                    chargingNonCellularProfileDefault: tvOS.chargingNonCellularProfileDefault
                )
            }
        }
    #else
        enum QualityProfiles {
            // macOS-specific settings
            enum macOS {
                static let qualityProfilesDefault = [
                    hd2160p60MPVProfile,
                    hd1080p60MPVProfile,
                    hd1080pMPVProfile,
                    hd720p60MPVProfile
                ]

                static let batteryCellularProfileDefault = hd1080p60MPVProfile.id
                static let batteryNonCellularProfileDefault = hd1080p60MPVProfile.id
                static let chargingCellularProfileDefault = hd1080p60MPVProfile.id
                static let chargingNonCellularProfileDefault = hd1080p60MPVProfile.id
            }

            // Access the correct profile for other platforms
            static var currentProfile: (qualityProfilesDefault: [QualityProfile], batteryCellularProfileDefault: String, batteryNonCellularProfileDefault: String, chargingCellularProfileDefault: String, chargingNonCellularProfileDefault: String) {
                (
                    qualityProfilesDefault: macOS.qualityProfilesDefault,
                    batteryCellularProfileDefault: macOS.batteryCellularProfileDefault,
                    batteryNonCellularProfileDefault: macOS.batteryNonCellularProfileDefault,
                    chargingCellularProfileDefault: macOS.chargingCellularProfileDefault,
                    chargingNonCellularProfileDefault: macOS.chargingNonCellularProfileDefault
                )
            }
        }
    #endif

    static let batteryCellularProfile = Key<QualityProfile.ID>(
        "batteryCellularProfile",
        default: QualityProfiles.currentProfile.batteryCellularProfileDefault
    )
    static let batteryNonCellularProfile = Key<QualityProfile.ID>(
        "batteryNonCellularProfile",
        default: QualityProfiles.currentProfile.batteryNonCellularProfileDefault
    )
    static let chargingCellularProfile = Key<QualityProfile.ID>(
        "chargingCellularProfile",
        default: QualityProfiles.currentProfile.chargingCellularProfileDefault
    )
    static let chargingNonCellularProfile = Key<QualityProfile.ID>(
        "chargingNonCellularProfile",
        default: QualityProfiles.currentProfile.chargingNonCellularProfileDefault
    )
    static let forceAVPlayerForLiveStreams = Key<Bool>(
        "forceAVPlayerForLiveStreams",
        default: true
    )
    static let qualityProfiles = Key<[QualityProfile]>(
        "qualityProfiles",
        default: QualityProfiles.currentProfile.qualityProfilesDefault
    )

    // MARK: GROUP - History

    static let saveRecents = Key<Bool>("saveRecents", default: true)
    static let saveHistory = Key<Bool>("saveHistory", default: true)
    static let showRecents = Key<Bool>("showRecents", default: true)
    static let limitRecents = Key<Bool>("limitRecents", default: false)
    static let limitRecentsAmount = Key<Int>("limitRecentsAmount", default: 10)
    static let showWatchingProgress = Key<Bool>("showWatchingProgress", default: true)
    static let saveLastPlayed = Key<Bool>("saveLastPlayed", default: false)

    static let watchedVideoPlayNowBehavior = Key<WatchedVideoPlayNowBehavior>("watchedVideoPlayNowBehavior", default: .continue)
    static let watchedThreshold = Key<Int>("watchedThreshold", default: 90)
    static let resetWatchedStatusOnPlaying = Key<Bool>("resetWatchedStatusOnPlaying", default: false)

    static let watchedVideoStyle = Key<WatchedVideoStyle>("watchedVideoStyle", default: .badge)
    static let watchedVideoBadgeColor = Key<WatchedVideoBadgeColor>("WatchedVideoBadgeColor", default: .red)
    static let showToggleWatchedStatusButton = Key<Bool>("showToggleWatchedStatusButton", default: false)

    // MARK: GROUP - SponsorBlock

    static let sponsorBlockInstance = Key<String>("sponsorBlockInstance", default: "https://sponsor.ajay.app")
    static let sponsorBlockCategories = Key<Set<String>>("sponsorBlockCategories", default: Set(SponsorBlockAPI.categories))
    static let sponsorBlockColors = Key<[String: String]>("sponsorBlockColors", default: SponsorBlockColors.dictionary)
    static let sponsorBlockShowTimeWithSkipsRemoved = Key<Bool>("sponsorBlockShowTimeWithSkipsRemoved", default: false)
    static let sponsorBlockShowCategoriesInTimeline = Key<Bool>("sponsorBlockShowCategoriesInTimeline", default: true)
    static let sponsorBlockShowNoticeAfterSkip = Key<Bool>("sponsorBlockShowNoticeAfterSkip", default: true)

    // MARK: GROUP - Locations

    static let instancesManifest = Key<String>("instancesManifest", default: "")
    static let countryOfPublicInstances = Key<String?>("countryOfPublicInstances")

    static let instances = Key<[Instance]>("instances", default: [])
    static let accounts = Key<[Account]>("accounts", default: [])

    // MARK: Group - Advanced

    static let showPlayNowInBackendContextMenu = Key<Bool>("showPlayNowInBackendContextMenu", default: false)
    static let videoLoadingRetryCount = Key<Int>("videoLoadingRetryCount", default: 10)

    static let showMPVPlaybackStats = Key<Bool>("showMPVPlaybackStats", default: false)
    static let mpvEnableLogging = Key<Bool>("mpvEnableLogging", default: false)
    static let mpvCacheSecs = Key<String>("mpvCacheSecs", default: "120")
    static let mpvCachePauseWait = Key<String>("mpvCachePauseWait", default: "3")
    static let mpvCachePauseInital = Key<Bool>("mpvCachePauseInitial", default: false)
    static let mpvDeinterlace = Key<Bool>("mpvDeinterlace", default: false)
    static let mpvHWdec = Key<String>("hwdec", default: "auto-safe")
    static let mpvDemuxerLavfProbeInfo = Key<String>("mpvDemuxerLavfProbeInfo", default: "no")
    static let mpvInitialAudioSync = Key<Bool>("mpvInitialAudioSync", default: true)
    static let mpvSetRefreshToContentFPS = Key<Bool>("mpvSetRefreshToContentFPS", default: false)

    static let showCacheStatus = Key<Bool>("showCacheStatus", default: false)
    static let feedCacheSize = Key<String>("feedCacheSize", default: "50")

    // MARK: GROUP - Other exportable

    static let lastAccountID = Key<Account.ID?>("lastAccountID")
    static let lastInstanceID = Key<Instance.ID?>("lastInstanceID")

    static let playerRate = Key<Double>("playerRate", default: 1.0)
    static let recentlyOpened = Key<[RecentItem]>("recentlyOpened", default: [])

    static let trendingCategory = Key<TrendingCategory>("trendingCategory", default: .default)
    static let trendingCountry = Key<Country>("trendingCountry", default: .us)

    static let subscriptionsViewPage = Key<SubscriptionsView.Page>("subscriptionsViewPage", default: .feed)

    static let subscriptionsListingStyle = Key<ListingStyle>("subscriptionsListingStyle", default: .cells)
    static let popularListingStyle = Key<ListingStyle>("popularListingStyle", default: .cells)
    static let trendingListingStyle = Key<ListingStyle>("trendingListingStyle", default: .cells)
    static let playlistListingStyle = Key<ListingStyle>("playlistListingStyle", default: .list)
    static let channelPlaylistListingStyle = Key<ListingStyle>("channelPlaylistListingStyle", default: .cells)
    static let searchListingStyle = Key<ListingStyle>("searchListingStyle", default: .cells)
    static let hideShorts = Key<Bool>("hideShorts", default: false)
    static let hideWatched = Key<Bool>("hideWatched", default: false)

    // MARK: GROUP - Not exportable

    static let queue = Key<[PlayerQueueItem]>("queue", default: [])
    static let playbackMode = Key<PlayerModel.PlaybackMode>("playbackMode", default: .queue)
    static let lastPlayed = Key<PlayerQueueItem?>("lastPlayed")

    static let activeBackend = Key<PlayerBackendType>("activeBackend", default: .mpv)
    static let captionsLanguageCode = Key<String?>("captionsLanguageCode")
    static let lastUsedPlaylistID = Key<Playlist.ID?>("lastPlaylistID")
    static let lastAccountIsPublic = Key<Bool>("lastAccountIsPublic", default: false)

    // MARK: LEGACY

    static let homeHistoryItems = Key<Int>("homeHistoryItems", default: 10)
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

    var value: Stream.Resolution {
        if let predefined = Stream.Resolution.PredefinedResolution(rawValue: rawValue) {
            return .predefined(predefined)
        }
        // Provide a default value of 720p 30
        return .custom(height: 720, refreshRate: 30)
    }

    var description: String {
        let resolution = value
        let height = resolution.height
        let refreshRate = resolution.refreshRate

        // Superscript labels
        let superscript4K = "⁴ᴷ"
        let superscriptHD = "ᴴᴰ"

        // Special handling for specific resolutions
        switch height {
        case 2160:
            // 4K superscript after the refresh rate
            return refreshRate == 30 ? "2160p \(superscript4K)" : "2160p\(refreshRate) \(superscript4K)"
        case 1440, 1080:
            // HD superscript after the refresh rate
            return refreshRate == 30 ? "\(height)p \(superscriptHD)" : "\(height)p\(refreshRate) \(superscriptHD)"
        default:
            // Default formatting for other resolutions
            return refreshRate == 30 ? "\(height)p" : "\(height)p\(refreshRate)"
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

enum StartupSection: String, CaseIterable, Defaults.Serializable {
    case home, subscriptions, popular, trending, playlists, search

    var label: String {
        rawValue.capitalized.localized()
    }

    var tabSelection: TabSelection {
        switch self {
        case .home:
            return .home
        case .subscriptions:
            return .subscriptions
        case .popular:
            return .popular
        case .trending:
            return .trending
        case .playlists:
            return .playlists
        case .search:
            return .search
        }
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

enum ButtonLabelStyle: String, CaseIterable, Defaults.Serializable {
    case iconOnly, iconAndText

    var text: Bool {
        self == .iconAndText
    }

    var description: String {
        switch self {
        case .iconOnly:
            return "Icon only".localized()
        case .iconAndText:
            return "Icon and text".localized()
        }
    }
}

enum ThumbnailsQuality: String, CaseIterable, Defaults.Serializable {
    case highest, high, medium, low

    var description: String {
        switch self {
        case .highest:
            return "Best quality".localized()
        case .high:
            return "High quality".localized()
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

enum ShowInspectorSetting: String, Defaults.Serializable {
    case always, onlyLocal
}

enum DetailsToolbarPositionSetting: String, CaseIterable, Defaults.Serializable {
    case left, center, right

    var needsLeftSpacer: Bool {
        self == .center || self == .right
    }

    var needsRightSpacer: Bool {
        self == .center || self == .left
    }
}

enum PlayerTapGestureAction: String, CaseIterable, Defaults.Serializable {
    case togglePlayerVisibility
    case togglePlayer
    case openChannel
    case nothing

    var label: String {
        switch self {
        case .togglePlayerVisibility:
            return "Toggle size"
        case .togglePlayer:
            return "Toggle player"
        case .openChannel:
            return "Open channel"
        case .nothing:
            return "Do nothing"
        }
    }
}

enum FullScreenRotationSetting: String, CaseIterable, Defaults.Serializable {
    case landscapeLeft
    case landscapeRight

    #if os(iOS)
        var interfaceOrientation: UIInterfaceOrientation {
            switch self {
            case .landscapeLeft:
                return .landscapeLeft
            case .landscapeRight:
                return .landscapeRight
            }
        }
    #endif
}

struct WidgetSettings: Defaults.Serializable {
    static let defaultLimit = 10
    static let maxLimit: [WidgetListingStyle: Int] = [
        .horizontalCells: 50,
        .list: 50
    ]

    static var bridge = WidgetSettingsBridge()

    var id: String
    var listingStyle = WidgetListingStyle.horizontalCells
    var limit = Self.defaultLimit

    var viewID: String {
        "\(id)-\(listingStyle.rawValue)-\(limit)"
    }

    static func maxLimit(_ style: WidgetListingStyle) -> Int {
        maxLimit[style] ?? defaultLimit
    }
}

struct WidgetSettingsBridge: Defaults.Bridge {
    typealias Value = WidgetSettings
    typealias Serializable = [String: String]

    func serialize(_ value: Value?) -> Serializable? {
        guard let value else { return nil }

        return [
            "id": value.id,
            "listingStyle": value.listingStyle.rawValue,
            "limit": String(value.limit)
        ]
    }

    func deserialize(_ object: Serializable?) -> Value? {
        guard let object, let id = object["id"], !id.isEmpty else { return nil }
        var listingStyle = WidgetListingStyle.horizontalCells
        if let style = object["listingStyle"] {
            listingStyle = WidgetListingStyle(rawValue: style) ?? .horizontalCells
        }
        let limit = Int(object["limit"] ?? "\(WidgetSettings.defaultLimit)") ?? WidgetSettings.defaultLimit

        return Value(
            id: id,
            listingStyle: listingStyle,
            limit: limit
        )
    }
}

enum WidgetListingStyle: String, CaseIterable, Defaults.Serializable {
    case horizontalCells
    case list
}

enum SponsorBlockColors: String {
    case sponsor = "#00D400" // Green
    case selfpromo = "#FFFF00" // Yellow
    case interaction = "#CC00FF" // Purple
    case intro = "#00FFFF" // Cyan
    case outro = "#0202ED" // Dark Blue
    case preview = "#008FD6" // Light Blue
    case filler = "#7300FF" // Violet
    case music_offtopic = "#FF9900" // Orange

    // Define all cases, can be used to iterate over the colors
    static let allCases: [SponsorBlockColors] = [Self.sponsor, Self.selfpromo, Self.interaction, Self.intro, Self.outro, Self.preview, Self.filler, Self.music_offtopic]

    // Create a dictionary with the category names as keys and colors as values
    static let dictionary: [String: String] = {
        var dict = [String: String]()
        for item in allCases {
            dict[String(describing: item)] = item.rawValue
        }
        return dict
    }()
}
