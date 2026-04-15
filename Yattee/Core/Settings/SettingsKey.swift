//
//  SettingsKey.swift
//  Yattee
//
//  Keys used for storing settings in UserDefaults and iCloud.
//

import Foundation

/// Keys for storing settings values.
/// Used internally by SettingsManager for persistence.
enum SettingsKey: String, CaseIterable {
    // General
    case theme
    case accentColor
    case showWatchedCheckmark

    // Playback
    case preferredQuality
    case cellularQuality
    case autoplay
    case backgroundPlayback
    case dashEnabled
    case preferredAudioLanguage
    case preferredSubtitlesLanguage
    case resumeAction

    // SponsorBlock
    case sponsorBlockEnabled
    case sponsorBlockCategories
    case sponsorBlockAPIURL

    // Return YouTube Dislike
    case returnYouTubeDislikeEnabled

    // DeArrow
    case deArrowEnabled
    case deArrowReplaceTitles
    case deArrowReplaceThumbnails
    case deArrowAPIURL
    case deArrowThumbnailAPIURL

    // Platform-specific
    case macPlayerMode
    case playerSheetAutoResize
    case listStyle

    // Feed
    case feedCacheValidityMinutes

    // Player
    case keepPlayerPinned
    case hapticFeedbackEnabled
    case hapticFeedbackIntensity
    case inAppOrientationLock
    case rotateToMatchAspectRatio
    case preferPortraitBrowsing

    // Home
    case homeShortcutOrder
    case homeShortcutVisibility
    case homeShortcutLayout
    case homeSectionOrder
    case homeSectionVisibility
    case homeSectionItemsLimit
    case homeSectionLayout

    // Tab Bar (compact size class)
    case tabBarItemOrder
    case tabBarItemVisibility
    case tabBarStartupTab

    // Sidebar
    case sidebarMainItemOrder
    case sidebarMainItemVisibility
    case sidebarStartupTab
    case sidebarSourcesEnabled
    case sidebarSourceSort
    case sidebarSourcesLimitEnabled
    case sidebarMaxSources
    case sidebarChannelsEnabled
    case sidebarMaxChannels
    case sidebarChannelSort
    case sidebarChannelsLimitEnabled
    case sidebarPlaylistsEnabled
    case sidebarMaxPlaylists
    case sidebarPlaylistSort
    case sidebarPlaylistsLimitEnabled

    // Remote Control
    case remoteControlCustomDeviceName
    case remoteControlHideWhenBackgrounded

    // Advanced
    case showAdvancedStreamDetails
    case showPlayerAreaDebug
    case showTVDebugButton
    case verboseMPVLogging
    case verboseRemoteControlLogging
    case mpvBufferSeconds
    case mpvUseEDLStreams
    case zoomTransitionsEnabled

    // Details panel
    case floatingDetailsPanelSide // Landscape only - which side the panel appears on
    case floatingDetailsPanelWidth // Resizable panel width in wide layout
    case landscapeDetailsPanelVisible
    case landscapeDetailsPanelPinned

    // Player Controls
    case activeControlsPresetID

    // Video Swipe Actions
    case videoSwipeActionOrder
    case videoSwipeActionVisibility

    // Onboarding
    case onboardingCompleted

    /// Whether this key should have platform-specific prefixes.
    /// Platform-specific keys are stored under a `iOS.` / `macOS.` / `tvOS.` prefix
    /// in both UserDefaults and iCloud, so each platform family syncs independently.
    var isPlatformSpecific: Bool {
        switch self {
        case .preferredQuality, .cellularQuality, .macPlayerMode, .listStyle,
             // Home layout — different UI paradigms per platform
             .homeShortcutOrder, .homeShortcutVisibility, .homeShortcutLayout,
             .homeSectionOrder, .homeSectionVisibility, .homeSectionItemsLimit, .homeSectionLayout,
             // Tab bar (compact size class) layout
             .tabBarItemOrder, .tabBarItemVisibility, .tabBarStartupTab,
             // Sidebar layout/selection
             .sidebarMainItemOrder, .sidebarMainItemVisibility, .sidebarStartupTab,
             .sidebarSourcesEnabled, .sidebarSourceSort, .sidebarSourcesLimitEnabled, .sidebarMaxSources,
             .sidebarChannelsEnabled, .sidebarMaxChannels, .sidebarChannelSort, .sidebarChannelsLimitEnabled,
             .sidebarPlaylistsEnabled, .sidebarMaxPlaylists, .sidebarPlaylistSort, .sidebarPlaylistsLimitEnabled,
             // Player details panel — iOS/iPadOS only, different on other platforms
             .floatingDetailsPanelSide, .floatingDetailsPanelWidth,
             .landscapeDetailsPanelVisible, .landscapeDetailsPanelPinned,
             // Video swipe actions — touch-gesture feature
             .videoSwipeActionOrder, .videoSwipeActionVisibility:
            return true
        default:
            return false
        }
    }

    /// Whether this key should only be stored locally (not synced to iCloud).
    /// Used for device-specific settings like custom device name for remote control.
    var isLocalOnly: Bool {
        switch self {
        case .remoteControlCustomDeviceName, .remoteControlHideWhenBackgrounded,
             .activeControlsPresetID,  // Per-device preset selection
             .onboardingCompleted:  // Per-device onboarding state
            return true
        default:
            return false
        }
    }
}
