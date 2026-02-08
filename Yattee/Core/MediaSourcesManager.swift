//
//  MediaSourcesManager.swift
//  Yattee
//
//  Manages configured media sources with persistence.
//

import Foundation
import Security

/// Manages the list of configured media sources.
@MainActor
@Observable
final class MediaSourcesManager {
    // MARK: - Storage

    private let localDefaults = UserDefaults.standard
    private let ubiquitousStore = NSUbiquitousKeyValueStore.default
    private let sourcesKey = "configuredMediaSources"
    private let iCloudSourcesKey = "syncedMediaSources"
    private let keychainServiceName = "com.yattee.mediasources"

    // MARK: - Dependencies

    private weak var settingsManager: SettingsManager?
    private weak var dataManager: DataManager?

    // MARK: - Sync State

    private var isImportingFromiCloud = false
    private var iCloudObserver: NSObjectProtocol?

    // MARK: - State

    private(set) var sources: [MediaSource] = []

    /// Tracks which sources have passwords stored (for reactive UI updates)
    private(set) var passwordStoredSourceIDs: Set<UUID> = []

    // MARK: - Initialization

    init(settingsManager: SettingsManager? = nil) {
        self.settingsManager = settingsManager
        loadSources()
        observeiCloudChanges()
        // Import or refresh network sources from iCloud on startup
        importFromiCloudOnStartupIfNeeded()
    }

    /// Imports or refreshes network sources (WebDAV and SMB) from iCloud on startup.
    /// - If no local network sources exist: imports all from iCloud (first-time setup).
    /// - If local network sources differ from iCloud: replaces local with iCloud data
    ///   (catches name changes, enable/disable toggles, etc. made on other devices while app was closed).
    private func importFromiCloudOnStartupIfNeeded() {
        guard iCloudSyncEnabled else {
            LoggingService.shared.debug("MediaSources startup: iCloud sync disabled, skipping import", category: .cloudKit)
            return
        }

        ubiquitousStore.synchronize()

        guard let data = ubiquitousStore.data(forKey: iCloudSourcesKey),
              let exports = try? JSONDecoder().decode([MediaSourceExport].self, from: data),
              !exports.isEmpty else {
            LoggingService.shared.debug("MediaSources startup: No network sources in iCloud", category: .cloudKit)
            return
        }

        let iCloudNetworkSources = exports.compactMap { $0.toMediaSource() }

        if networkSources.isEmpty {
            // First-time import: no local network sources
            LoggingService.shared.info("MediaSources startup: Importing \(iCloudNetworkSources.count) network sources from iCloud", category: .cloudKit)
            sources.append(contentsOf: iCloudNetworkSources)
            saveSources()
            refreshPasswordStoredStatus()
        } else if networkSources != iCloudNetworkSources {
            // Existing sources differ from iCloud - refresh from iCloud
            // This catches name changes, enable/disable toggles, etc. made on other devices
            LoggingService.shared.info("MediaSources startup: Refreshing \(iCloudNetworkSources.count) network sources from iCloud (local differs)", category: .cloudKit)
            isImportingFromiCloud = true
            defer { isImportingFromiCloud = false }
            let localFolderSources = sources.filter { $0.type == .localFolder }
            sources = localFolderSources + iCloudNetworkSources
            saveSources()
            refreshPasswordStoredStatus()
        } else {
            LoggingService.shared.debug("MediaSources startup: Local sources match iCloud, no update needed", category: .cloudKit)
        }
    }

    /// Sets the settings manager reference (for dependency injection after init).
    func configure(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    /// Sets the data manager reference (for cleanup when sources are deleted).
    func setDataManager(_ manager: DataManager) {
        self.dataManager = manager
    }

    // MARK: - Source Management

    /// Adds a new media source.
    func add(_ source: MediaSource) {
        sources.append(source)
        saveSources()
        syncToiCloudIfNeeded()
    }

    /// Removes a media source and its stored credentials.
    func remove(_ source: MediaSource) {
        // Clean up associated data (history, bookmarks, playlist items)
        dataManager?.removeAllDataForMediaSource(sourceID: source.id)

        // Remove from Home cards/sections
        settingsManager?.removeFromHome(sourceID: source.id)

        sources.removeAll { $0.id == source.id }
        saveSources()
        syncToiCloudIfNeeded()

        // Remove password from Keychain (for network sources)
        if source.type == .webdav || source.type == .smb {
            deletePassword(for: source)
        }
    }

    /// Updates an existing media source.
    func update(_ source: MediaSource) {
        if let index = sources.firstIndex(where: { $0.id == source.id }) {
            sources[index] = source
            saveSources()
            syncToiCloudIfNeeded()
        }
    }

    /// Toggles the enabled state of a source.
    func toggleEnabled(_ source: MediaSource) {
        if let index = sources.firstIndex(where: { $0.id == source.id }) {
            var updated = sources[index]
            updated.isEnabled.toggle()
            sources[index] = updated
            saveSources()
            syncToiCloudIfNeeded()
        }
    }

    // MARK: - Computed Properties

    var enabledSources: [MediaSource] {
        sources.filter(\.isEnabled)
    }

    var webdavSources: [MediaSource] {
        sources.filter { $0.type == .webdav }
    }
    
    var smbSources: [MediaSource] {
        sources.filter { $0.type == .smb }
    }

    /// All network sources (WebDAV and SMB) that can be synced to iCloud.
    var networkSources: [MediaSource] {
        sources.filter { $0.type == .webdav || $0.type == .smb }
    }

    var localFolderSources: [MediaSource] {
        sources.filter { $0.type == .localFolder }
    }

    var isEmpty: Bool {
        sources.isEmpty
    }

    /// Returns true if this network source (WebDAV or SMB) needs password to be configured.
    /// Uses the tracked set for reactive UI updates.
    func needsPassword(for source: MediaSource) -> Bool {
        guard source.type == .webdav || source.type == .smb else { return false }
        return !passwordStoredSourceIDs.contains(source.id)
    }

    /// Returns true if any network source needs password.
    var hasSourcesNeedingPassword: Bool {
        networkSources.contains { needsPassword(for: $0) }
    }

    /// Find source by UUID.
    func source(byID id: UUID) -> MediaSource? {
        sources.first { $0.id == id }
    }

    // MARK: - Persistence

    private func loadSources() {
        if let data = localDefaults.data(forKey: sourcesKey),
           let decoded = try? JSONDecoder().decode([MediaSource].self, from: data) {
            sources = decoded
            refreshPasswordStoredStatus()
            cleanupOrphanedHomeItems()
        }
    }
    
    /// Removes Home items for sources that no longer exist
    private func cleanupOrphanedHomeItems() {
        let validSourceIDs = Set(sources.map(\.id))
        settingsManager?.cleanupOrphanedHomeMediaSourceItems(validSourceIDs: validSourceIDs)
    }

    /// Refreshes the set of source IDs that have passwords stored (for network sources).
    /// Call this when app returns from background to sync with Keychain state.
    func refreshPasswordStoredStatus() {
        let previousIDs = passwordStoredSourceIDs
        passwordStoredSourceIDs = Set(
            sources.filter { $0.type == .webdav || $0.type == .smb }
                .filter { password(for: $0) != nil }
                .map(\.id)
        )

        // Log if status changed (helps debug auth issues)
        if previousIDs != passwordStoredSourceIDs {
            let added = passwordStoredSourceIDs.subtracting(previousIDs)
            let removed = previousIDs.subtracting(passwordStoredSourceIDs)
            LoggingService.shared.info(
                "Password status changed",
                category: .keychain,
                details: "added=\(added.count), removed=\(removed.count)"
            )
        }
    }

    private func saveSources() {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        localDefaults.set(data, forKey: sourcesKey)
    }

    // MARK: - Keychain (Passwords)

    /// Stores a password for a WebDAV/SMB source in the Keychain.
    /// Password syncs to iCloud Keychain when iCloud sync is enabled for media sources.
    func setPassword(_ password: String, for source: MediaSource) {
        let account = source.id.uuidString
        guard let data = password.data(using: .utf8) else {
            LoggingService.shared.error("Failed to encode password data", category: .keychain)
            return
        }

        let syncEnabled = shouldSyncCredentialsToiCloud

        // First, delete any existing item (both synced and non-synced) to avoid duplicates
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Create new item with current sync preference
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: syncEnabled,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        if status == errSecSuccess {
            LoggingService.shared.info(
                "Stored password for \(source.name)",
                category: .keychain,
                details: "iCloudSync=\(syncEnabled)"
            )
            // Update tracked set for reactive UI
            passwordStoredSourceIDs.insert(source.id)
        } else {
            LoggingService.shared.error(
                "Failed to store password for \(source.name)",
                category: .keychain,
                details: "status=\(status)"
            )
        }
    }

    /// Retrieves the password for a WebDAV/SMB source from the Keychain.
    /// Searches both synced and non-synced items.
    func password(for source: MediaSource) -> String? {
        let account = source.id.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            LoggingService.shared.debug(
                "No password found for \(source.name)",
                category: .keychain,
                details: "status=\(status)"
            )
            return nil
        }

        LoggingService.shared.debug("Retrieved password for \(source.name)", category: .keychain)
        return password
    }

    /// Deletes the password for a source from the Keychain.
    /// Deletes both synced and non-synced items.
    func deletePassword(for source: MediaSource) {
        let account = source.id.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            LoggingService.shared.info("Deleted password for \(source.name)", category: .keychain)
        } else {
            LoggingService.shared.error(
                "Failed to delete password for \(source.name)",
                category: .keychain,
                details: "status=\(status)"
            )
        }

        // Update tracked set for reactive UI
        passwordStoredSourceIDs.remove(source.id)
    }

    // MARK: - Bookmarks (Local Folders)

    /// Updates the bookmark data for a local folder source.
    func updateBookmark(_ bookmarkData: Data, for source: MediaSource) {
        if let index = sources.firstIndex(where: { $0.id == source.id }) {
            var updated = sources[index]
            updated.bookmarkData = bookmarkData
            sources[index] = updated
            saveSources()
        }
    }

    /// Resolves and accesses a local folder source.
    /// - Parameter source: The local folder source.
    /// - Returns: The resolved URL, or nil if bookmark resolution failed.
    func resolveLocalFolderURL(for source: MediaSource) -> URL? {
        guard source.type == .localFolder,
              let bookmarkData = source.bookmarkData else {
            return source.url
        }

        var isStale = false

        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif

        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            // If bookmark is stale, we should re-create it
            // but we can't do that without user interaction
            return url
        } catch {
            return nil
        }
    }

    // MARK: - iCloud Sync

    /// Whether iCloud sync is enabled and media sources sync is enabled.
    private var iCloudSyncEnabled: Bool {
        settingsManager?.iCloudSyncEnabled == true && settingsManager?.syncMediaSources == true
    }

    /// Whether credentials should sync to iCloud Keychain (when iCloud sync is enabled for media sources).
    private var shouldSyncCredentialsToiCloud: Bool {
        iCloudSyncEnabled
    }

    /// Syncs network sources to iCloud if sync is enabled and not currently importing.
    private func syncToiCloudIfNeeded() {
        guard iCloudSyncEnabled, !isImportingFromiCloud else { return }
        syncToiCloud()
    }

    /// Syncs all network sources (WebDAV and SMB) to iCloud.
    /// Note: Local folder sources are never synced as they are device-specific.
    func syncToiCloud() {
        guard iCloudSyncEnabled else {
            LoggingService.shared.debug("MediaSources: iCloud sync disabled, skipping", category: .cloudKit)
            return
        }

        let networkSources = sources.filter { $0.type == .webdav || $0.type == .smb }
        let exports = networkSources.map { MediaSourceExport(from: $0) }

        let sourceNames = exports.map { "\($0.id): \($0.name)" }.joined(separator: ", ")
        LoggingService.shared.info("MediaSources: Syncing \(exports.count) network sources to iCloud", category: .cloudKit, details: sourceNames)

        if let data = try? JSONEncoder().encode(exports) {
            ubiquitousStore.set(data, forKey: iCloudSourcesKey)
            ubiquitousStore.synchronize()
            LoggingService.shared.debug("MediaSources: Synced to iCloud successfully", category: .cloudKit)
        }
    }

    /// Replaces local network sources (WebDAV and SMB) with iCloud data.
    /// Preserves local folder sources which are device-specific.
    func replaceWithiCloudData() {
        guard let data = ubiquitousStore.data(forKey: iCloudSourcesKey),
              let exports = try? JSONDecoder().decode([MediaSourceExport].self, from: data) else {
            LoggingService.shared.debug("MediaSources: replaceWithiCloudData - No data in iCloud or decode failed", category: .cloudKit)
            return
        }

        isImportingFromiCloud = true
        defer { isImportingFromiCloud = false }

        let sourceNames = exports.map { "\($0.id): \($0.name)" }.joined(separator: ", ")
        LoggingService.shared.info("MediaSources: Replacing with \(exports.count) network sources from iCloud", category: .cloudKit, details: sourceNames)

        // Keep local folder sources
        let localFolderSources = sources.filter { $0.type == .localFolder }

        // Convert exports to sources (WebDAV and SMB)
        let iCloudNetworkSources = exports.compactMap { $0.toMediaSource() }

        // Merge: local folders + iCloud network sources
        sources = localFolderSources + iCloudNetworkSources
        saveSources()

        // Refresh password status for UI reactivity
        refreshPasswordStoredStatus()

        LoggingService.shared.info("MediaSources: Now have \(sources.count) sources (\(networkSources.count) network, \(localFolderSources.count) local)", category: .cloudKit)
    }

    /// Observes iCloud key-value store changes.
    private func observeiCloudChanges() {
        iCloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: ubiquitousStore,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }

            // Log the change reason
            let changeReason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            Task { @MainActor in
                LoggingService.shared.debug("MediaSources: iCloud external change - reason=\(changeReason ?? -1), keys=\(changedKeys)", category: .cloudKit)
            }

            // Check if our key was changed
            guard changedKeys.contains(self.iCloudSourcesKey) else {
                Task { @MainActor in
                    LoggingService.shared.debug("MediaSources: iCloud change not for media sources key, ignoring", category: .cloudKit)
                }
                return
            }

            Task { @MainActor [weak self] in
                guard let self else { return }

                // Check sync settings
                guard self.iCloudSyncEnabled else {
                    LoggingService.shared.debug("MediaSources: iCloud sync disabled, ignoring external change", category: .cloudKit)
                    return
                }

                LoggingService.shared.info("MediaSources: Processing iCloud external change", category: .cloudKit)
                self.replaceWithiCloudData()
            }
        }

        // Synchronize to get latest values
        ubiquitousStore.synchronize()
    }
}

// MARK: - Preview Support

extension MediaSourcesManager {
    /// Preview manager with sample data.
    static var preview: MediaSourcesManager {
        let manager = MediaSourcesManager()
        manager.sources = [
            .webdav(name: "My NAS", url: URL(string: "https://nas.local:5006")!, username: "user"),
            .localFolder(name: "Downloads", url: URL(fileURLWithPath: "/Users/user/Downloads"))
        ]
        return manager
    }
}
