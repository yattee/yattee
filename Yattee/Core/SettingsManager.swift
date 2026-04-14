//
//  SettingsManager.swift
//  Yattee
//
//  Manages user settings with iCloud sync via NSUbiquitousKeyValueStore.
//

import Foundation
import SwiftUI
#if os(iOS)
import CoreHaptics
import UIKit
#endif

/// Manages application settings with platform-specific keys and iCloud sync.
@MainActor
@Observable
final class SettingsManager {
    // MARK: - Storage

    let ubiquitousStore = NSUbiquitousKeyValueStore.default
    let localDefaults = UserDefaults.standard

    // MARK: - Backing Storage for @Observable
    // These stored properties trigger observation when modified.
    // Internal access for extension use.

    // Theme
    var _theme: AppTheme?
    var _accentColor: AccentColor?
    var _showWatchedCheckmark: Bool?

    // Playback
    var _preferredQuality: VideoQuality?
    var _cellularQuality: VideoQuality?
    var _backgroundPlaybackEnabled: Bool?
    var _dashEnabled: Bool?
    var _preferredAudioLanguage: String?
    var _preferredSubtitlesLanguage: String?
    var _playerVolume: Float?
    var _resumeAction: ResumeAction?

    // SponsorBlock
    var _sponsorBlockEnabled: Bool?
    var _sponsorBlockCategories: Set<SponsorBlockCategory>?
    var _sponsorBlockAPIURL: String?

    // Return YouTube Dislike & DeArrow
    var _returnYouTubeDislikeEnabled: Bool?
    var _deArrowEnabled: Bool?
    var _deArrowReplaceTitles: Bool?
    var _deArrowReplaceThumbnails: Bool?
    var _deArrowAPIURL: String?
    var _deArrowThumbnailAPIURL: String?

    // User Agent
    var _customUserAgent: String?
    var _randomizeUserAgentPerRequest: Bool?

    // Feed
    var _feedCacheValidityMinutes: Int?

    // Player
    var _keepPlayerPinnedEnabled: Bool?
    #if os(iOS)
    var _inAppOrientationLock: Bool?
    var _rotateToMatchAspectRatio: Bool?
    var _preferPortraitBrowsing: Bool?
    #endif
    #if os(macOS)
    var _macPlayerMode: MacPlayerMode?
    var _playerSheetAutoResize: Bool?
    #endif

    // Mini Player Minimize Behavior is kept as it's not part of the preset

    // Mini Player Minimize Behavior (iOS 26+)
    #if os(iOS)
    var _miniPlayerMinimizeBehavior: (any RawRepresentable)?
    #endif

    // Haptics (iOS)
    #if os(iOS)
    var _hapticFeedbackEnabled: Bool?
    var _hapticFeedbackIntensity: HapticFeedbackIntensity?
    #endif

    // iCloud sync
    var _iCloudSyncEnabled: Bool?
    var _lastSyncTime: Date?
    var _syncInstances: Bool?
    var _syncSubscriptions: Bool?
    var _syncBookmarks: Bool?
    var _syncPlaybackHistory: Bool?
    var _syncPlaylists: Bool?
    var _syncSettings: Bool?
    var _syncMediaSources: Bool?
    var _syncSearchHistory: Bool?

    // Search history
    var _searchHistoryLimit: Int?

    // Home settings
    var _homeShortcutOrder: [HomeShortcutItem]?
    var _homeShortcutVisibility: [HomeShortcutItem: Bool]?
    var _homeShortcutLayout: HomeShortcutLayout?
    var _homeSectionOrder: [HomeSectionItem]?
    var _homeSectionVisibility: [HomeSectionItem: Bool]?
    var _homeSectionItemsLimit: Int?

    // Tab bar settings (compact size class only - iOS)
    var _tabBarItemOrder: [TabBarItem]?
    var _tabBarItemVisibility: [TabBarItem: Bool]?

    // Sidebar settings
    var _sidebarMainItemOrder: [SidebarMainItem]?
    var _sidebarMainItemVisibility: [SidebarMainItem: Bool]?
    var _sidebarStartupTab: SidebarMainItem?

    // Tab bar startup
    var _tabBarStartupTab: SidebarMainItem?
    var _sidebarSourcesEnabled: Bool?
    var _sidebarSourceSort: SidebarSourceSort?
    var _sidebarSourcesLimitEnabled: Bool?
    var _sidebarMaxSources: Int?
    var _sidebarChannelsEnabled: Bool?
    var _sidebarMaxChannels: Int?
    var _sidebarChannelSort: SidebarChannelSort?
    var _sidebarChannelsLimitEnabled: Bool?
    var _sidebarPlaylistsEnabled: Bool?
    var _sidebarMaxPlaylists: Int?
    var _sidebarPlaylistSort: SidebarPlaylistSort?
    var _sidebarPlaylistsLimitEnabled: Bool?

    // iCloud startup sync protection
    /// When true, suppresses iCloud writes from set() methods to prevent
    /// stale local values from overwriting newer iCloud data during app startup.
    var isInitialSyncPending = false

    // Advanced settings
    var _showAdvancedStreamDetails: Bool?
    var _showPlayerAreaDebug: Bool?
    var _showTVDebugButton: Bool?
    var _verboseMPVLogging: Bool?
    var _verboseRemoteControlLogging: Bool?
    var _mpvBufferSeconds: Double?
    var _mpvUseEDLStreams: Bool?
    var _zoomTransitionsEnabled: Bool?

    // Details panel settings
    var _floatingDetailsPanelSide: FloatingPanelSide?
    var _floatingDetailsPanelWidth: CGFloat?
    var _landscapeDetailsPanelVisible: Bool?
    var _landscapeDetailsPanelPinned: Bool?

    // Notification settings
    var _backgroundNotificationsEnabled: Bool?
    var _defaultNotificationsForNewChannels: Bool?
    var _lastBackgroundCheck: Date?
    var _clipboardURLDetectionEnabled: Bool?
    var _incognitoModeEnabled: Bool?
    var _historyRetentionDays: Int?
    var _saveWatchHistory: Bool?
    var _saveRecentSearches: Bool?
    var _saveRecentChannels: Bool?
    var _saveRecentPlaylists: Bool?

    // Subscription account settings
    var _subscriptionAccount: SubscriptionAccount?

    // Queue settings
    var _queueEnabled: Bool?
    var _queueAutoPlayNext: Bool?
    var _queueAutoPlayCountdown: Int?

    // Handoff settings
    var _handoffEnabled: Bool?

    // Remote Control settings
    var _remoteControlCustomDeviceName: String?
    var _remoteControlHideWhenBackgrounded: Bool?

    // Link action settings
    var _defaultLinkAction: DefaultLinkAction?

    // Video tap actions (iOS/macOS only)
    #if !os(tvOS)
    var _thumbnailTapAction: VideoTapAction?
    var _textAreaTapAction: VideoTapAction?
    #endif

    // Player Controls settings (controlsButtonSize moved to preset)

    // Appearance settings
    var _listStyle: VideoListStyle?
    #if os(iOS)
    var _appIcon: AppIcon?
    #endif

    // Video Swipe Actions
    #if !os(tvOS)
    var _videoSwipeActionOrder: [VideoSwipeAction]?
    var _videoSwipeActionVisibility: [VideoSwipeAction: Bool]?
    #endif

    // MARK: - Initialization

    /// Logs KVStore change reason for debugging iCloud account switches.
    private func logKVStoreChangeReason(_ reason: Int) {
        let reasonDescription: String
        switch reason {
        case NSUbiquitousKeyValueStoreServerChange:
            reasonDescription = "ServerChange"
        case NSUbiquitousKeyValueStoreInitialSyncChange:
            reasonDescription = "InitialSyncChange"
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            reasonDescription = "QuotaViolationChange"
        case NSUbiquitousKeyValueStoreAccountChange:
            reasonDescription = "AccountChange (iCloud account switched!)"
            LoggingService.shared.logCloudKit("SettingsManager: iCloud account changed - settings will sync with new account")
        default:
            reasonDescription = "Unknown(\(reason))"
        }
        
        LoggingService.shared.logCloudKit("SettingsManager KVStore change: \(reasonDescription)")
    }
    
    init() {
        // Listen for external changes from iCloud
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: ubiquitousStore,
            queue: .main
        ) { [weak self] notification in
            let changeReason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]

            // Only process iCloud changes if sync is enabled
            Task { @MainActor [weak self] in
                // Log change reason for debugging account switches
                if let changeReason {
                    self?.logKVStoreChangeReason(changeReason)
                }

                if let changedKeys {
                    LoggingService.shared.logCloudKit("SettingsManager KVStore changed keys: \(changedKeys)")
                }

                guard let self, self.iCloudSyncEnabled else { return }
                let keySet = changedKeys.map { Set($0) }
                self.refreshFromiCloud(changedKeys: keySet)
                self.updateLastSyncTime()
            }
        }

        // One-shot migration: move legacy unprefixed values for keys that became
        // platform-specific into their new iOS./macOS./tvOS. slots. Must run before
        // the initial iCloud refresh so it can seed the prefixed iCloud slot from the
        // current local value before any remote data is read.
        migrateLayoutKeysToPlatformPrefixed()

        // Initial sync from iCloud to local storage (async to avoid blocking app launch)
        // This ensures local defaults have the latest iCloud values before any reads.
        // While sync is pending, suppress iCloud writes from set() to prevent stale
        // local values from overwriting newer iCloud data.
        if localDefaults.bool(forKey: "iCloudSyncEnabled") {
            isInitialSyncPending = true
            LoggingService.shared.logCloudKit("SettingsManager.init: isInitialSyncPending = true, suppressing iCloud writes until refresh completes")
            Task { @MainActor [weak self] in
                defer {
                    self?.isInitialSyncPending = false
                    LoggingService.shared.logCloudKit("SettingsManager.init: isInitialSyncPending = false, iCloud writes re-enabled")
                }
                self?.ubiquitousStore.synchronize()
                self?.refreshFromiCloud()
            }
        }
    }

    // MARK: - Storage Helpers
    // Internal access for extension use.

    func platformKey(_ key: SettingsKey) -> String {
        let baseKey = key.rawValue
        #if os(iOS)
        return key.isPlatformSpecific ? "iOS.\(baseKey)" : baseKey
        #elseif os(macOS)
        return key.isPlatformSpecific ? "macOS.\(baseKey)" : baseKey
        #elseif os(tvOS)
        return key.isPlatformSpecific ? "tvOS.\(baseKey)" : baseKey
        #endif
    }

    /// Returns the companion key used to store the last-modified timestamp for a protected setting.
    func modifiedAtKey(for key: SettingsKey) -> String {
        "\(platformKey(key))_modifiedAt"
    }

    func string(for key: SettingsKey) -> String? {
        // Always read from local storage to avoid blocking on iCloud XPC calls
        return localDefaults.string(forKey: platformKey(key))
    }

    func bool(for key: SettingsKey, default defaultValue: Bool = false) -> Bool {
        // Always read from local storage to avoid blocking on iCloud XPC calls
        let pKey = platformKey(key)
        if localDefaults.object(forKey: pKey) != nil {
            return localDefaults.bool(forKey: pKey)
        }
        return defaultValue
    }

    func data(for key: SettingsKey) -> Data? {
        // Always read from local storage to avoid blocking on iCloud XPC calls
        return localDefaults.data(forKey: platformKey(key))
    }

    func integer(for key: SettingsKey, default defaultValue: Int) -> Int {
        // Always read from local storage to avoid blocking on iCloud XPC calls
        let pKey = platformKey(key)
        if localDefaults.object(forKey: pKey) != nil {
            return localDefaults.integer(forKey: pKey)
        }
        return defaultValue
    }

    func double(for key: SettingsKey) -> Double {
        // Always read from local storage to avoid blocking on iCloud XPC calls
        return localDefaults.double(forKey: platformKey(key))
    }

    func set(_ value: String, for key: SettingsKey) {
        let pKey = platformKey(key)
        localDefaults.set(value, forKey: pKey)

        // Only write to iCloud if sync is enabled, settings sync is enabled, key is not local-only,
        // and initial sync has completed (to prevent stale values overwriting iCloud during startup)
        if iCloudSyncEnabled && syncSettings && !key.isLocalOnly && !isInitialSyncPending {
            ubiquitousStore.set(value, forKey: pKey)
        } else if isInitialSyncPending && !key.isLocalOnly {
            LoggingService.shared.logCloudKit("set(String): suppressed iCloud write for \(pKey) (initial sync pending)")
        }
    }

    func set(_ value: Bool, for key: SettingsKey) {
        let pKey = platformKey(key)
        localDefaults.set(value, forKey: pKey)

        if iCloudSyncEnabled && syncSettings && !key.isLocalOnly && !isInitialSyncPending {
            ubiquitousStore.set(value, forKey: pKey)
        } else if isInitialSyncPending && !key.isLocalOnly {
            LoggingService.shared.logCloudKit("set(Bool): suppressed iCloud write for \(pKey) (initial sync pending)")
        }
    }

    func set(_ value: Data, for key: SettingsKey) {
        let pKey = platformKey(key)
        localDefaults.set(value, forKey: pKey)

        if iCloudSyncEnabled && syncSettings && !key.isLocalOnly && !isInitialSyncPending {
            ubiquitousStore.set(value, forKey: pKey)
        } else if isInitialSyncPending && !key.isLocalOnly {
            LoggingService.shared.logCloudKit("set(Data): suppressed iCloud write for \(pKey) (initial sync pending)")
        }
    }

    func set(_ value: Int, for key: SettingsKey) {
        let pKey = platformKey(key)
        localDefaults.set(value, forKey: pKey)

        if iCloudSyncEnabled && syncSettings && !key.isLocalOnly && !isInitialSyncPending {
            ubiquitousStore.set(value, forKey: pKey)
        } else if isInitialSyncPending && !key.isLocalOnly {
            LoggingService.shared.logCloudKit("set(Int): suppressed iCloud write for \(pKey) (initial sync pending)")
        }
    }

    func set(_ value: Double, for key: SettingsKey) {
        let pKey = platformKey(key)
        localDefaults.set(value, forKey: pKey)

        if iCloudSyncEnabled && syncSettings && !key.isLocalOnly && !isInitialSyncPending {
            ubiquitousStore.set(value, forKey: pKey)
        } else if isInitialSyncPending && !key.isLocalOnly {
            LoggingService.shared.logCloudKit("set(Double): suppressed iCloud write for \(pKey) (initial sync pending)")
        }
    }

    // MARK: - Cache Management

    /// Clears cached values to force re-read from storage
    func clearCache() {
        _theme = nil
        _accentColor = nil
        _showWatchedCheckmark = nil
        _preferredQuality = nil
        _cellularQuality = nil
        _backgroundPlaybackEnabled = nil
        _dashEnabled = nil
        _preferredAudioLanguage = nil
        _preferredSubtitlesLanguage = nil
        _playerVolume = nil
        _resumeAction = nil
        _sponsorBlockEnabled = nil
        _sponsorBlockCategories = nil
        _sponsorBlockAPIURL = nil
        _returnYouTubeDislikeEnabled = nil
        _deArrowEnabled = nil
        _deArrowReplaceTitles = nil
        _deArrowReplaceThumbnails = nil
        _deArrowAPIURL = nil
        _deArrowThumbnailAPIURL = nil
        _customUserAgent = nil
        _randomizeUserAgentPerRequest = nil
        _feedCacheValidityMinutes = nil
        _keepPlayerPinnedEnabled = nil
        #if os(iOS)
        _hapticFeedbackEnabled = nil
        _hapticFeedbackIntensity = nil
        _inAppOrientationLock = nil
        _rotateToMatchAspectRatio = nil
        _preferPortraitBrowsing = nil
        #endif
        _iCloudSyncEnabled = nil
        _lastSyncTime = nil
        _syncInstances = nil
        _syncSubscriptions = nil
        _syncBookmarks = nil
        _syncPlaybackHistory = nil
        _syncPlaylists = nil
        _syncSettings = nil
        _syncMediaSources = nil
        _syncSearchHistory = nil
        _searchHistoryLimit = nil
        #if os(macOS)
        _macPlayerMode = nil
        _playerSheetAutoResize = nil
        #endif
        // miniPlayerShowVideo and miniPlayerVideoTapAction moved to preset
        #if os(iOS)
        _miniPlayerMinimizeBehavior = nil
        #endif
        _homeShortcutOrder = nil
        _homeShortcutVisibility = nil
        _homeShortcutLayout = nil
        _homeSectionOrder = nil
        _homeSectionVisibility = nil
        _homeSectionItemsLimit = nil
        _tabBarItemOrder = nil
        _tabBarItemVisibility = nil
        _sidebarMainItemOrder = nil
        _sidebarMainItemVisibility = nil
        _sidebarStartupTab = nil
        _tabBarStartupTab = nil
        _sidebarSourcesEnabled = nil
        _sidebarSourceSort = nil
        _sidebarSourcesLimitEnabled = nil
        _sidebarMaxSources = nil
        _sidebarChannelsEnabled = nil
        _sidebarMaxChannels = nil
        _sidebarChannelSort = nil
        _sidebarChannelsLimitEnabled = nil
        _sidebarPlaylistsEnabled = nil
        _sidebarMaxPlaylists = nil
        _sidebarPlaylistSort = nil
        _sidebarPlaylistsLimitEnabled = nil
        _showAdvancedStreamDetails = nil
        _showPlayerAreaDebug = nil
        _showTVDebugButton = nil
        _verboseMPVLogging = nil
        _verboseRemoteControlLogging = nil
        _mpvBufferSeconds = nil
        _mpvUseEDLStreams = nil
        _zoomTransitionsEnabled = nil
        _floatingDetailsPanelSide = nil
        _floatingDetailsPanelWidth = nil
        _landscapeDetailsPanelVisible = nil
        _landscapeDetailsPanelPinned = nil
        _backgroundNotificationsEnabled = nil
        _defaultNotificationsForNewChannels = nil
        _lastBackgroundCheck = nil
        _clipboardURLDetectionEnabled = nil
        _incognitoModeEnabled = nil
        _historyRetentionDays = nil
        _saveWatchHistory = nil
        _saveRecentSearches = nil
        _saveRecentChannels = nil
        _saveRecentPlaylists = nil
        _subscriptionAccount = nil
        _queueEnabled = nil
        _queueAutoPlayNext = nil
        _queueAutoPlayCountdown = nil
        _handoffEnabled = nil
        _defaultLinkAction = nil
        _remoteControlCustomDeviceName = nil
        _remoteControlHideWhenBackgrounded = nil
        #if !os(tvOS)
        _thumbnailTapAction = nil
        _textAreaTapAction = nil
        #endif
        _listStyle = nil
        #if os(iOS)
        _appIcon = nil
        #endif
        #if !os(tvOS)
        _videoSwipeActionOrder = nil
        _videoSwipeActionVisibility = nil
        #endif
    }
}
