//
//  SettingsManager+General.swift
//  Yattee
//
//  General settings: theme, feed, queue, notifications, privacy, user agent, links.
//

import Foundation
#if os(iOS)
import UIKit
#endif

extension SettingsManager {
    // MARK: - Theme Settings

    var theme: AppTheme {
        get {
            if let cached = _theme { return cached }
            return AppTheme(rawValue: string(for: .theme) ?? "") ?? .system
        }
        set {
            _theme = newValue
            set(newValue.rawValue, for: .theme)
        }
    }

    var accentColor: AccentColor {
        get {
            if let cached = _accentColor { return cached }
            return AccentColor(rawValue: string(for: .accentColor) ?? "") ?? .default
        }
        set {
            _accentColor = newValue
            set(newValue.rawValue, for: .accentColor)
        }
    }

    // MARK: - App Icon Settings (iOS only)

    #if os(iOS)
    var appIcon: AppIcon {
        get {
            if let cached = _appIcon { return cached }
            guard let rawValue = localDefaults.string(forKey: "appIcon"),
                  let icon = AppIcon(rawValue: rawValue) else {
                return .default
            }
            return icon
        }
        set {
            _appIcon = newValue
            localDefaults.set(newValue.rawValue, forKey: "appIcon")

            // Apply the icon change
            Task { @MainActor in
                do {
                    try await UIApplication.shared.setAlternateIconName(newValue.alternateIconName)
                } catch {
                    LoggingService.shared.error("Failed to set alternate icon: \(error)", category: .general)
                }
            }
        }
    }
    #endif

    /// Whether to show a checkmark badge on fully watched video thumbnails.
    /// Default is true (enabled).
    var showWatchedCheckmark: Bool {
        get {
            if let cached = _showWatchedCheckmark { return cached }
            return bool(for: .showWatchedCheckmark, default: true)
        }
        set {
            _showWatchedCheckmark = newValue
            set(newValue, for: .showWatchedCheckmark)
        }
    }

    // MARK: - Feed Settings

    /// Feed cache validity duration in minutes. Default is 30 minutes.
    static let defaultFeedCacheValidityMinutes = 30

    var feedCacheValidityMinutes: Int {
        get {
            if let cached = _feedCacheValidityMinutes { return cached }
            return integer(for: .feedCacheValidityMinutes, default: Self.defaultFeedCacheValidityMinutes)
        }
        set {
            _feedCacheValidityMinutes = newValue
            set(newValue, for: .feedCacheValidityMinutes)
        }
    }

    /// Feed cache validity duration in seconds (computed from minutes).
    var feedCacheValiditySeconds: TimeInterval {
        TimeInterval(feedCacheValidityMinutes * 60)
    }

    // MARK: - Custom User-Agent

    /// Generates a new random User-Agent string.
    static func generateRandomUserAgent() -> String {
        UserAgentGenerator.generateRandom()
    }

    /// Returns the current effective User-Agent string.
    /// If randomize per request is enabled, generates a new random UA.
    /// Otherwise, returns the stored custom user agent.
    /// This is nonisolated so it can be called from any context.
    nonisolated static func currentUserAgent() -> String {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "randomizeUserAgentPerRequest") {
            return UserAgentGenerator.generateRandom()
        }
        return defaults.string(forKey: "customUserAgent") ?? UserAgentGenerator.defaultUserAgent
    }

    /// The custom User-Agent string used for all HTTP requests.
    /// This setting is stored locally only and not synced to iCloud.
    var customUserAgent: String {
        get {
            if let cached = _customUserAgent { return cached }
            // Only read from local defaults - never sync this setting
            return localDefaults.string(forKey: "customUserAgent") ?? UserAgentGenerator.defaultUserAgent
        }
        set {
            _customUserAgent = newValue
            // Store only in local defaults - this setting should not sync
            localDefaults.set(newValue, forKey: "customUserAgent")
        }
    }

    /// Randomizes the custom User-Agent to a new random value.
    func randomizeUserAgent() {
        customUserAgent = UserAgentGenerator.generateRandom()
    }

    /// Whether to generate a new random User-Agent for each HTTP request.
    /// When enabled, customUserAgent is ignored and a fresh random UA is used per request.
    /// This setting is stored locally only and not synced to iCloud.
    var randomizeUserAgentPerRequest: Bool {
        get {
            if let cached = _randomizeUserAgentPerRequest { return cached }
            return localDefaults.bool(forKey: "randomizeUserAgentPerRequest")
        }
        set {
            _randomizeUserAgentPerRequest = newValue
            localDefaults.set(newValue, forKey: "randomizeUserAgentPerRequest")
        }
    }

    // MARK: - Queue Settings

    /// Whether the queue feature is enabled. Default is true.
    /// When disabled, tapping videos plays them directly without queue options.
    var queueEnabled: Bool {
        get {
            if let cached = _queueEnabled { return cached }
            // Default to true if not set
            let value: Bool
            if localDefaults.object(forKey: "queueEnabled") == nil {
                value = true
            } else {
                value = localDefaults.bool(forKey: "queueEnabled")
            }
            _queueEnabled = value  // Cache on first read
            return value
        }
        set {
            _queueEnabled = newValue
            localDefaults.set(newValue, forKey: "queueEnabled")
        }
    }

    /// Whether auto-play next video in queue is enabled. Default is true.
    /// When enabled, the next video in queue plays automatically when current video ends.
    var queueAutoPlayNext: Bool {
        get {
            if let cached = _queueAutoPlayNext { return cached }
            // Default to true if not set
            if localDefaults.object(forKey: "queueAutoPlayNext") == nil {
                return true
            }
            return localDefaults.bool(forKey: "queueAutoPlayNext")
        }
        set {
            _queueAutoPlayNext = newValue
            localDefaults.set(newValue, forKey: "queueAutoPlayNext")
        }
    }

    /// Countdown duration in seconds before auto-playing next video. Default is 5.
    /// Range: 1-15 seconds.
    var queueAutoPlayCountdown: Int {
        get {
            if let cached = _queueAutoPlayCountdown { return cached }
            // Default to 5 if not set
            if localDefaults.object(forKey: "queueAutoPlayCountdown") == nil {
                return 5
            }
            return localDefaults.integer(forKey: "queueAutoPlayCountdown")
        }
        set {
            // Clamp to valid range
            let clamped = max(1, min(15, newValue))
            _queueAutoPlayCountdown = clamped
            localDefaults.set(clamped, forKey: "queueAutoPlayCountdown")
        }
    }

    // MARK: - Subscription Account Settings

    /// The subscription account storage key.
    private static let subscriptionAccountKey = "subscriptionAccount"

    /// The active subscription account configuration.
    /// Determines where subscriptions are stored and fetched from.
    /// Defaults to local (iCloud) if not set.
    var subscriptionAccount: SubscriptionAccount {
        get {
            if let cached = _subscriptionAccount { return cached }
            guard let data = localDefaults.data(forKey: Self.subscriptionAccountKey),
                  let account = try? JSONDecoder().decode(SubscriptionAccount.self, from: data) else {
                return .local
            }
            return account
        }
        set {
            _subscriptionAccount = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                localDefaults.set(data, forKey: Self.subscriptionAccountKey)
                // Sync to iCloud if enabled
                if iCloudSyncEnabled && syncSettings {
                    ubiquitousStore.set(data, forKey: Self.subscriptionAccountKey)
                }
            }
        }
    }

    // MARK: - Notification Settings

    /// Whether background notifications are enabled. Default is false.
    /// When enabled, the app will periodically check for new videos in the background
    /// and send local notifications for channels with notifications enabled.
    var backgroundNotificationsEnabled: Bool {
        get {
            if let cached = _backgroundNotificationsEnabled { return cached }
            return localDefaults.bool(forKey: "backgroundNotificationsEnabled")
        }
        set {
            _backgroundNotificationsEnabled = newValue
            localDefaults.set(newValue, forKey: "backgroundNotificationsEnabled")
        }
    }

    /// Whether to detect video URLs from clipboard when app becomes active.
    /// Only applies to external site URLs (not YouTube). Default is false.
    var clipboardURLDetectionEnabled: Bool {
        get {
            if let cached = _clipboardURLDetectionEnabled { return cached }
            // Default to false
            let value = localDefaults.object(forKey: "clipboardURLDetectionEnabled") as? Bool
            return value ?? false
        }
        set {
            _clipboardURLDetectionEnabled = newValue
            localDefaults.set(newValue, forKey: "clipboardURLDetectionEnabled")
        }
    }

    /// Default notification state for newly subscribed channels. Default is false.
    /// When true, new subscriptions will have notifications enabled by default.
    var defaultNotificationsForNewChannels: Bool {
        get {
            if let cached = _defaultNotificationsForNewChannels { return cached }
            return localDefaults.bool(forKey: "defaultNotificationsForNewChannels")
        }
        set {
            _defaultNotificationsForNewChannels = newValue
            localDefaults.set(newValue, forKey: "defaultNotificationsForNewChannels")
        }
    }

    /// The last time background notification check was performed.
    /// This is separate from the main feed cache's lastUpdated timestamp.
    var lastBackgroundCheck: Date? {
        get {
            if let cached = _lastBackgroundCheck { return cached }
            return localDefaults.object(forKey: "lastBackgroundCheck") as? Date
        }
        set {
            _lastBackgroundCheck = newValue
            localDefaults.set(newValue, forKey: "lastBackgroundCheck")
        }
    }

    /// Last notified video ID per channel (keyed by channel ID).
    /// Used to prevent duplicate notifications for the same video.
    /// Not cached since it's only accessed during infrequent background refreshes.
    var lastNotifiedVideoPerChannel: [String: String] {
        get {
            localDefaults.dictionary(forKey: "lastNotifiedVideoPerChannel") as? [String: String] ?? [:]
        }
        set {
            localDefaults.set(newValue, forKey: "lastNotifiedVideoPerChannel")
        }
    }

    // MARK: - Privacy Settings

    /// Whether incognito mode is enabled. When enabled, watch history is not recorded.
    /// This is a local-only setting (not synced to iCloud). Default is false.
    var incognitoModeEnabled: Bool {
        get {
            if let cached = _incognitoModeEnabled { return cached }
            let value = localDefaults.object(forKey: "incognitoModeEnabled") as? Bool
            return value ?? false
        }
        set {
            _incognitoModeEnabled = newValue
            localDefaults.set(newValue, forKey: "incognitoModeEnabled")
        }
    }

    /// Number of days after which watch history entries are automatically deleted.
    /// Set to 0 to disable auto-deletion. Default is 90 days.
    static let defaultHistoryRetentionDays = 90

    var historyRetentionDays: Int {
        get {
            if let cached = _historyRetentionDays { return cached }
            if localDefaults.object(forKey: "historyRetentionDays") == nil {
                return Self.defaultHistoryRetentionDays
            }
            return localDefaults.integer(forKey: "historyRetentionDays")
        }
        set {
            _historyRetentionDays = newValue
            localDefaults.set(newValue, forKey: "historyRetentionDays")
        }
    }

    /// Whether to save watch history entries. Default is true.
    /// When disabled, new watch history entries won't be saved. Existing entries remain visible.
    /// Incognito mode overrides this setting.
    var saveWatchHistory: Bool {
        get {
            if let cached = _saveWatchHistory { return cached }
            if localDefaults.object(forKey: "saveWatchHistory") == nil {
                return true
            }
            let value = localDefaults.bool(forKey: "saveWatchHistory")
            _saveWatchHistory = value
            return value
        }
        set {
            _saveWatchHistory = newValue
            localDefaults.set(newValue, forKey: "saveWatchHistory")
        }
    }

    /// Whether to save recent search queries. Default is true.
    /// When disabled, new search queries won't be saved. Existing entries remain visible.
    /// Incognito mode overrides this setting.
    var saveRecentSearches: Bool {
        get {
            if let cached = _saveRecentSearches { return cached }
            if localDefaults.object(forKey: "saveRecentSearches") == nil {
                return true
            }
            let value = localDefaults.bool(forKey: "saveRecentSearches")
            _saveRecentSearches = value
            return value
        }
        set {
            _saveRecentSearches = newValue
            localDefaults.set(newValue, forKey: "saveRecentSearches")
        }
    }

    /// Whether to save recently visited channels. Default is true.
    /// When disabled, new channel visits won't be saved. Existing entries remain visible.
    /// Incognito mode overrides this setting.
    var saveRecentChannels: Bool {
        get {
            if let cached = _saveRecentChannels { return cached }
            if localDefaults.object(forKey: "saveRecentChannels") == nil {
                return true
            }
            let value = localDefaults.bool(forKey: "saveRecentChannels")
            _saveRecentChannels = value
            return value
        }
        set {
            _saveRecentChannels = newValue
            localDefaults.set(newValue, forKey: "saveRecentChannels")
        }
    }

    /// Whether to save recently visited playlists. Default is true.
    /// When disabled, new playlist visits won't be saved. Existing entries remain visible.
    /// Incognito mode overrides this setting.
    var saveRecentPlaylists: Bool {
        get {
            if let cached = _saveRecentPlaylists { return cached }
            if localDefaults.object(forKey: "saveRecentPlaylists") == nil {
                return true
            }
            let value = localDefaults.bool(forKey: "saveRecentPlaylists")
            _saveRecentPlaylists = value
            return value
        }
        set {
            _saveRecentPlaylists = newValue
            localDefaults.set(newValue, forKey: "saveRecentPlaylists")
        }
    }

    /// Number of search queries to keep in history. Default is 25.
    var searchHistoryLimit: Int {
        get {
            if let cached = _searchHistoryLimit { return cached }
            let value = localDefaults.integer(forKey: "searchHistoryLimit")
            return value > 0 ? value : 25  // Default to 25
        }
        set {
            _searchHistoryLimit = newValue
            localDefaults.set(newValue, forKey: "searchHistoryLimit")
        }
    }

    // MARK: - Handoff Settings

    /// Whether Apple Handoff is enabled on this device. Default is false.
    /// When enabled, the app broadcasts its current activity for continuation on other devices.
    /// This is a local-only setting (not synced to iCloud).
    var handoffEnabled: Bool {
        get {
            if let cached = _handoffEnabled { return cached }
            // Default to false if not set
            if localDefaults.object(forKey: "handoffEnabled") == nil {
                return false
            }
            return localDefaults.bool(forKey: "handoffEnabled")
        }
        set {
            _handoffEnabled = newValue
            localDefaults.set(newValue, forKey: "handoffEnabled")
        }
    }

    // MARK: - Link Action Settings

    /// Default action when opening links from share extension or URL schemes.
    /// Options: Open (play), Download, Ask every time. Default is "open".
    /// This is a local-only setting (not synced to iCloud).
    var defaultLinkAction: DefaultLinkAction {
        get {
            if let cached = _defaultLinkAction { return cached }
            guard let rawValue = localDefaults.string(forKey: "defaultLinkAction"),
                  let action = DefaultLinkAction(rawValue: rawValue) else {
                return .open
            }
            return action
        }
        set {
            _defaultLinkAction = newValue
            localDefaults.set(newValue.rawValue, forKey: "defaultLinkAction")
        }
    }

    // MARK: - Video Tap Actions (iOS/macOS only)

    #if !os(tvOS)
    /// Action to perform when tapping on video thumbnails. Default is playVideo.
    var thumbnailTapAction: VideoTapAction {
        get {
            if let cached = _thumbnailTapAction { return cached }
            guard let rawValue = localDefaults.string(forKey: "thumbnailTapAction"),
                  let action = VideoTapAction(rawValue: rawValue) else {
                return .playVideo
            }
            return action
        }
        set {
            _thumbnailTapAction = newValue
            localDefaults.set(newValue.rawValue, forKey: "thumbnailTapAction")
        }
    }

    /// Action to perform when tapping on video text area (title/author/metadata). Default is openInfo.
    var textAreaTapAction: VideoTapAction {
        get {
            if let cached = _textAreaTapAction { return cached }
            guard let rawValue = localDefaults.string(forKey: "textAreaTapAction"),
                  let action = VideoTapAction(rawValue: rawValue) else {
                return .openInfo
            }
            return action
        }
        set {
            _textAreaTapAction = newValue
            localDefaults.set(newValue.rawValue, forKey: "textAreaTapAction")
        }
    }
    #endif

    // MARK: - Video Tap Action (tvOS only)

    #if os(tvOS)
    /// Action to perform when clicking a video cell on tvOS. Default is openInfo.
    var tvOSVideoTapAction: VideoTapAction {
        get {
            if let cached = _tvOSVideoTapAction { return cached }
            guard let rawValue = localDefaults.string(forKey: "tvOSVideoTapAction"),
                  let action = VideoTapAction(rawValue: rawValue) else {
                return .openInfo
            }
            return action
        }
        set {
            _tvOSVideoTapAction = newValue
            localDefaults.set(newValue.rawValue, forKey: "tvOSVideoTapAction")
        }
    }
    #endif

    // MARK: - Onboarding

    /// Whether onboarding has been completed on this device.
    /// This is a local-only setting (not synced to iCloud) so each device shows onboarding once.
    var onboardingCompleted: Bool {
        get { localDefaults.bool(forKey: SettingsKey.onboardingCompleted.rawValue) }
        set { localDefaults.set(newValue, forKey: SettingsKey.onboardingCompleted.rawValue) }
    }
}
