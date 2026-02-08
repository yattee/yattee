//
//  SettingsManager+CloudSync.swift
//  Yattee
//
//  iCloud sync settings and sync category toggles.
//

import Foundation

extension SettingsManager {
    // MARK: - Home Visibility Sync Protection
    
    /// Keys that require special handling during sync to preserve user customizations.
    /// These settings should not be overwritten by default/stale values from iCloud.
    private static let protectedVisibilityKeys: Set<SettingsKey> = [
        .homeShortcutVisibility,
        .homeSectionVisibility,
        .homeShortcutOrder,
        .homeSectionOrder
    ]
    
    /// Checks if the given home shortcut visibility data represents user customization (differs from defaults).
    private func homeShortcutVisibilityHasCustomization(_ data: Data?) -> Bool {
        guard let data,
              let visibility = try? JSONDecoder().decode([HomeShortcutItem: Bool].self, from: data) else {
            return false
        }
        
        let defaults = HomeShortcutItem.defaultVisibility
        
        // Check if any value differs from the default
        for (item, isVisible) in visibility {
            if let defaultValue = defaults[item], defaultValue != isVisible {
                return true
            }
        }
        
        // Also check if there are items in visibility that aren't in defaults (user added custom items)
        for item in visibility.keys {
            if defaults[item] == nil {
                return true
            }
        }
        
        return false
    }
    
    /// Checks if the given home section visibility data represents user customization (differs from defaults).
    private func homeSectionVisibilityHasCustomization(_ data: Data?) -> Bool {
        guard let data,
              let visibility = try? JSONDecoder().decode([HomeSectionItem: Bool].self, from: data) else {
            return false
        }
        
        let defaults = HomeSectionItem.defaultVisibility
        
        // Check if any value differs from the default
        for (item, isVisible) in visibility {
            if let defaultValue = defaults[item], defaultValue != isVisible {
                return true
            }
        }
        
        // Also check if there are items in visibility that aren't in defaults (user added custom items)
        for item in visibility.keys {
            if defaults[item] == nil {
                return true
            }
        }
        
        return false
    }
    
    /// Determines whether local data should be preserved during iCloud sync using timestamp comparison.
    /// Returns true if the local write is newer than the iCloud write, meaning we should keep local.
    /// Falls back to customization-vs-defaults logic when no timestamps exist (migration path).
    private func shouldPreserveLocal(for key: SettingsKey) -> Bool {
        let tsKey = modifiedAtKey(for: key)
        let localTimestamp = localDefaults.double(forKey: tsKey)
        let iCloudTimestamp = ubiquitousStore.double(forKey: tsKey)

        // If both have timestamps, compare them
        if localTimestamp > 0 || iCloudTimestamp > 0 {
            if localTimestamp > iCloudTimestamp {
                LoggingService.shared.logCloudKit(
                    "Preserving local \(key.rawValue) - local timestamp \(localTimestamp) > iCloud \(iCloudTimestamp)"
                )
                return true
            } else if iCloudTimestamp > localTimestamp {
                LoggingService.shared.logCloudKit(
                    "Using iCloud \(key.rawValue) - iCloud timestamp \(iCloudTimestamp) > local \(localTimestamp)"
                )
                return false
            }
            // Equal timestamps - fall through to legacy logic
        }

        // Legacy fallback: no timestamps yet, use customization-vs-defaults comparison
        // Only applicable for visibility keys that have customization detection
        let pKey = platformKey(key)
        let localData = localDefaults.data(forKey: pKey)
        let iCloudData = ubiquitousStore.data(forKey: pKey)

        let localHasCustomization: Bool
        let iCloudHasCustomization: Bool

        switch key {
        case .homeShortcutVisibility:
            localHasCustomization = homeShortcutVisibilityHasCustomization(localData)
            iCloudHasCustomization = homeShortcutVisibilityHasCustomization(iCloudData)
        case .homeSectionVisibility:
            localHasCustomization = homeSectionVisibilityHasCustomization(localData)
            iCloudHasCustomization = homeSectionVisibilityHasCustomization(iCloudData)
        default:
            // For order keys without timestamps, don't preserve (no way to compare)
            return false
        }

        if localHasCustomization && !iCloudHasCustomization {
            LoggingService.shared.logCloudKit(
                "Preserving local \(key.rawValue) - local has customizations, iCloud has defaults (no timestamps)"
            )
            return true
        }

        if iCloudHasCustomization {
            LoggingService.shared.logCloudKit(
                "Using iCloud \(key.rawValue) - iCloud has user customizations (no timestamps)"
            )
        }

        return false
    }
    
    /// Pushes local protected settings to iCloud when local was preserved.
    /// Also pushes the companion _modifiedAt timestamps to keep them consistent.
    private func pushLocalToiCloudForPreservedKeys(_ keysToPreserve: Set<SettingsKey>) {
        for key in keysToPreserve {
            let pKey = platformKey(key)
            if let data = localDefaults.data(forKey: pKey) {
                ubiquitousStore.set(data, forKey: pKey)
                LoggingService.shared.logCloudKit(
                    "Pushed local \(key.rawValue) to iCloud (local was preserved)"
                )
            }
            // Also push the timestamp so other devices see the correct modified time
            let tsKey = modifiedAtKey(for: key)
            let localTimestamp = localDefaults.double(forKey: tsKey)
            if localTimestamp > 0 {
                ubiquitousStore.set(localTimestamp, forKey: tsKey)
            }
        }
    }
    // MARK: - iCloud Sync Settings

    /// Whether iCloud sync is enabled. When disabled, all data is stored locally only.
    /// Default is false (disabled).
    var iCloudSyncEnabled: Bool {
        get {
            if let cached = _iCloudSyncEnabled { return cached }
            // Only check local defaults for this setting - it should not sync to iCloud
            return localDefaults.bool(forKey: "iCloudSyncEnabled")
        }
        set {
            _iCloudSyncEnabled = newValue
            // Store only in local defaults - this setting should not sync
            localDefaults.set(newValue, forKey: "iCloudSyncEnabled")

            if newValue {
                // When enabling, update last sync time
                updateLastSyncTime()
            }
        }
    }

    /// The last time data was synced with iCloud.
    var lastSyncTime: Date? {
        get {
            if let cached = _lastSyncTime { return cached }
            return localDefaults.object(forKey: "lastSyncTime") as? Date
        }
        set {
            _lastSyncTime = newValue
            localDefaults.set(newValue, forKey: "lastSyncTime")
        }
    }

    /// Updates the last sync time to now.
    func updateLastSyncTime() {
        lastSyncTime = Date()
    }

    // MARK: - iCloud Sync Category Toggles

    /// Whether instances should be synced to iCloud. Default is true when iCloud sync is enabled.
    var syncInstances: Bool {
        get {
            if let cached = _syncInstances { return cached }
            // Default to true if not set (for backwards compatibility)
            if localDefaults.object(forKey: "syncInstances") == nil {
                return true
            }
            return localDefaults.bool(forKey: "syncInstances")
        }
        set {
            _syncInstances = newValue
            localDefaults.set(newValue, forKey: "syncInstances")
        }
    }

    /// Whether subscriptions should be synced to iCloud. Default is true when iCloud sync is enabled.
    var syncSubscriptions: Bool {
        get {
            if let cached = _syncSubscriptions { return cached }
            if localDefaults.object(forKey: "syncSubscriptions") == nil {
                return true
            }
            return localDefaults.bool(forKey: "syncSubscriptions")
        }
        set {
            _syncSubscriptions = newValue
            localDefaults.set(newValue, forKey: "syncSubscriptions")
        }
    }

    /// Whether bookmarks should be synced to iCloud. Default is true when iCloud sync is enabled.
    var syncBookmarks: Bool {
        get {
            if let cached = _syncBookmarks { return cached }
            if localDefaults.object(forKey: "syncBookmarks") == nil {
                return true
            }
            return localDefaults.bool(forKey: "syncBookmarks")
        }
        set {
            _syncBookmarks = newValue
            localDefaults.set(newValue, forKey: "syncBookmarks")
        }
    }

    /// Whether playback history should be synced to iCloud. Default is true when iCloud sync is enabled.
    var syncPlaybackHistory: Bool {
        get {
            if let cached = _syncPlaybackHistory { return cached }
            if localDefaults.object(forKey: "syncPlaybackHistory") == nil {
                return true
            }
            return localDefaults.bool(forKey: "syncPlaybackHistory")
        }
        set {
            _syncPlaybackHistory = newValue
            localDefaults.set(newValue, forKey: "syncPlaybackHistory")
        }
    }

    /// Whether playlists should be synced to iCloud. Default is true when iCloud sync is enabled.
    var syncPlaylists: Bool {
        get {
            if let cached = _syncPlaylists { return cached }
            if localDefaults.object(forKey: "syncPlaylists") == nil {
                return true
            }
            return localDefaults.bool(forKey: "syncPlaylists")
        }
        set {
            _syncPlaylists = newValue
            localDefaults.set(newValue, forKey: "syncPlaylists")
        }
    }

    /// Whether settings should be synced to iCloud. Default is true when iCloud sync is enabled.
    var syncSettings: Bool {
        get {
            if let cached = _syncSettings { return cached }
            if localDefaults.object(forKey: "syncSettings") == nil {
                return true
            }
            return localDefaults.bool(forKey: "syncSettings")
        }
        set {
            _syncSettings = newValue
            localDefaults.set(newValue, forKey: "syncSettings")
        }
    }

    /// Whether media sources (WebDAV only) should be synced to iCloud. Default is true when iCloud sync is enabled.
    /// Note: Local folder sources are never synced as they are device-specific.
    var syncMediaSources: Bool {
        get {
            if let cached = _syncMediaSources { return cached }
            if localDefaults.object(forKey: "syncMediaSources") == nil {
                return true
            }
            return localDefaults.bool(forKey: "syncMediaSources")
        }
        set {
            _syncMediaSources = newValue
            localDefaults.set(newValue, forKey: "syncMediaSources")
        }
    }

    /// Whether search history should be synced to iCloud. Default is true when iCloud sync is enabled.
    var syncSearchHistory: Bool {
        get {
            if let cached = _syncSearchHistory { return cached }
            if localDefaults.object(forKey: "syncSearchHistory") == nil {
                return true
            }
            return localDefaults.bool(forKey: "syncSearchHistory")
        }
        set {
            _syncSearchHistory = newValue
            localDefaults.set(newValue, forKey: "syncSearchHistory")
        }
    }

    /// Enables all sync categories. Called when enabling iCloud sync for the first time.
    func enableAllSyncCategories() {
        syncInstances = true
        syncSubscriptions = true
        syncBookmarks = true
        syncPlaybackHistory = true
        syncPlaylists = true
        syncSettings = true
        syncMediaSources = true
        syncSearchHistory = true
    }

    // MARK: - Sync Operations

    /// Syncs local settings to iCloud (called when enabling iCloud sync).
    /// Only syncs if settings sync is enabled.
    func syncToiCloud() {
        guard syncSettings else { return }

        // Copy all local settings to iCloud
        for key in SettingsKey.allCases {
            let pKey = platformKey(key)
            if let value = localDefaults.object(forKey: pKey) {
                ubiquitousStore.set(value, forKey: pKey)
            }
        }
        ubiquitousStore.synchronize()
        updateLastSyncTime()
    }

    /// Replaces local settings with iCloud data (called when enabling iCloud sync).
    /// Only replaces if settings sync is enabled.
    /// Protected settings are preserved if the local write is newer (timestamp-based).
    func replaceWithiCloudData() {
        guard syncSettings else { return }

        ubiquitousStore.synchronize()

        // Determine which protected keys to preserve before syncing
        var keysToPreserve = Set<SettingsKey>()
        for key in Self.protectedVisibilityKeys {
            if shouldPreserveLocal(for: key) {
                keysToPreserve.insert(key)
            }
        }

        // Copy all iCloud settings to local defaults
        for key in SettingsKey.allCases {
            // Skip protected keys that should preserve local values
            if keysToPreserve.contains(key) {
                continue
            }

            let pKey = platformKey(key)
            if let value = ubiquitousStore.object(forKey: pKey) {
                localDefaults.set(value, forKey: pKey)
            }

            // Also copy companion timestamps for protected keys when accepting iCloud values
            if Self.protectedVisibilityKeys.contains(key) {
                let tsKey = modifiedAtKey(for: key)
                let iCloudTimestamp = ubiquitousStore.double(forKey: tsKey)
                if iCloudTimestamp > 0 {
                    localDefaults.set(iCloudTimestamp, forKey: tsKey)
                }
            }
        }

        // Push local values to iCloud for keys we preserved
        if !keysToPreserve.isEmpty {
            pushLocalToiCloudForPreservedKeys(keysToPreserve)
        }

        clearCache()
        updateLastSyncTime()
    }

    /// Refreshes settings from iCloud by copying iCloud values to local storage.
    /// When `changedKeys` is provided (from the notification), only those keys are synced.
    /// Protected settings are preserved if the local write is newer (timestamp-based).
    func refreshFromiCloud(changedKeys: Set<String>? = nil) {
        guard syncSettings else { return }

        // Determine which protected keys to preserve before syncing
        var keysToPreserve = Set<SettingsKey>()
        for key in Self.protectedVisibilityKeys {
            if shouldPreserveLocal(for: key) {
                keysToPreserve.insert(key)
            }
        }

        // Copy settings from iCloud to local defaults
        for key in SettingsKey.allCases {
            // Skip local-only keys (device-specific settings that shouldn't sync)
            if key.isLocalOnly {
                continue
            }

            let pKey = platformKey(key)

            // If we have a changed-keys set, skip keys that didn't change
            if let changedKeys, !changedKeys.contains(pKey) {
                continue
            }

            // Skip protected keys that should preserve local values
            if keysToPreserve.contains(key) {
                continue
            }

            if let value = ubiquitousStore.object(forKey: pKey) {
                localDefaults.set(value, forKey: pKey)
            }

            // Also copy companion timestamps for protected keys when accepting iCloud values
            if Self.protectedVisibilityKeys.contains(key) {
                let tsKey = modifiedAtKey(for: key)
                let iCloudTimestamp = ubiquitousStore.double(forKey: tsKey)
                if iCloudTimestamp > 0 {
                    localDefaults.set(iCloudTimestamp, forKey: tsKey)
                }
            }
        }

        // Push local values to iCloud for keys we preserved
        if !keysToPreserve.isEmpty {
            pushLocalToiCloudForPreservedKeys(keysToPreserve)
        }

        // Clear caches to force re-read from local storage
        clearCache()
    }
}
