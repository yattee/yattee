//
//  InvidiousCredentialsManager.swift
//  Yattee
//
//  Manages Invidious session credentials stored securely in the Keychain.
//

import Foundation
import Security

/// Manages Invidious session IDs (SID) stored securely in the Keychain.
@MainActor
@Observable
final class InvidiousCredentialsManager: InstanceCredentialsManager {
    private let keychainServiceName = "com.yattee.invidious"
    private let thumbnailCacheKey = "com.yattee.invidious.channelThumbnails"

    /// Tracks which instances have stored sessions (for reactive UI updates)
    private(set) var loggedInInstanceIDs: Set<UUID> = []

    /// In-memory cache for channel thumbnails (channelID -> URL string)
    private var thumbnailCache: [String: String] = [:]

    /// Reference to settings manager for cleanup on logout and iCloud sync decisions
    weak var settingsManager: SettingsManager?

    /// Whether credentials should sync to iCloud Keychain (when iCloud sync is enabled for instances).
    private var shouldSyncToiCloud: Bool {
        settingsManager?.iCloudSyncEnabled == true && settingsManager?.syncInstances == true
    }

    init() {
        loadThumbnailCache()
    }

    // MARK: - Thumbnail Cache

    /// Gets cached thumbnail URL for a channel.
    func thumbnailURL(forChannelID channelID: String) -> URL? {
        guard let urlString = thumbnailCache[channelID] else { return nil }
        return URL(string: urlString)
    }

    /// Caches a thumbnail URL for a channel.
    func setThumbnailURL(_ url: URL, forChannelID channelID: String) {
        thumbnailCache[channelID] = url.absoluteString
        saveThumbnailCache()
    }

    /// Caches multiple thumbnail URLs at once.
    func setThumbnailURLs(_ thumbnails: [String: URL]) {
        for (channelID, url) in thumbnails {
            thumbnailCache[channelID] = url.absoluteString
        }
        saveThumbnailCache()
    }

    /// Returns channel IDs that are not in the cache.
    func uncachedChannelIDs(from channelIDs: [String]) -> [String] {
        channelIDs.filter { thumbnailCache[$0] == nil }
    }

    /// Clears the thumbnail cache.
    func clearThumbnailCache() {
        thumbnailCache.removeAll()
        UserDefaults.standard.removeObject(forKey: thumbnailCacheKey)
    }

    private func loadThumbnailCache() {
        if let data = UserDefaults.standard.data(forKey: thumbnailCacheKey),
           let cache = try? JSONDecoder().decode([String: String].self, from: data) {
            thumbnailCache = cache
        }
    }

    private func saveThumbnailCache() {
        if let data = try? JSONEncoder().encode(thumbnailCache) {
            UserDefaults.standard.set(data, forKey: thumbnailCacheKey)
        }
    }

    // MARK: - Public API

    /// Stores the SID (session ID) for an Invidious instance.
    /// SID syncs to iCloud Keychain when iCloud sync is enabled for instances.
    /// - Parameters:
    ///   - sid: The session ID cookie value
    ///   - instance: The Invidious instance
    func setSID(_ sid: String, for instance: Instance) {
        let account = instance.id.uuidString
        guard let data = sid.data(using: .utf8) else {
            LoggingService.shared.error("Failed to encode SID data", category: .keychain)
            return
        }

        let syncEnabled = shouldSyncToiCloud

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
                "Stored SID for Invidious instance",
                category: .keychain,
                details: "instanceID=\(instance.id), iCloudSync=\(syncEnabled)"
            )
            // Update tracked set for reactive UI
            loggedInInstanceIDs.insert(instance.id)
        } else {
            LoggingService.shared.error(
                "Failed to store SID for Invidious instance",
                category: .keychain,
                details: "instanceID=\(instance.id), status=\(status)"
            )
        }
    }

    /// Retrieves the SID for an Invidious instance.
    /// Searches both synced and non-synced items.
    /// - Parameter instance: The Invidious instance
    /// - Returns: The session ID if stored, nil otherwise
    func sid(for instance: Instance) -> String? {
        let account = instance.id.uuidString

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
              let sid = String(data: data, encoding: .utf8) else {
            LoggingService.shared.debug(
                "No SID found for Invidious instance",
                category: .keychain,
                details: "instanceID=\(instance.id), status=\(status)"
            )
            return nil
        }

        LoggingService.shared.debug(
            "Retrieved SID for Invidious instance",
            category: .keychain,
            details: "instanceID=\(instance.id)"
        )
        return sid
    }

    /// Deletes the SID for an instance (logout).
    /// Deletes both synced and non-synced items.
    /// - Parameter instance: The Invidious instance
    func deleteSID(for instance: Instance) {
        let account = instance.id.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            LoggingService.shared.info(
                "Deleted SID for Invidious instance",
                category: .keychain,
                details: "instanceID=\(instance.id)"
            )
        } else {
            LoggingService.shared.error(
                "Failed to delete SID for Invidious instance",
                category: .keychain,
                details: "instanceID=\(instance.id), status=\(status)"
            )
        }

        // Update tracked set for reactive UI
        loggedInInstanceIDs.remove(instance.id)

        // Clear Feed cache (but keep Feed items in Home settings - toggle will be disabled)
        HomeInstanceCache.shared.clear(instanceID: instance.id, contentType: .feed)
    }

    /// Checks if an instance has a stored session.
    /// - Parameter instance: The Invidious instance
    /// - Returns: true if logged in, false otherwise
    func isLoggedIn(for instance: Instance) -> Bool {
        // Check tracked set first for performance
        if loggedInInstanceIDs.contains(instance.id) {
            return true
        }
        // Fall back to Keychain check
        let hasSession = sid(for: instance) != nil
        if hasSession {
            loggedInInstanceIDs.insert(instance.id)
        }
        return hasSession
    }

    /// Refreshes the logged-in status for an instance.
    /// Call this when the view appears to ensure UI is in sync.
    func refreshLoginStatus(for instance: Instance) {
        if sid(for: instance) != nil {
            loggedInInstanceIDs.insert(instance.id)
        } else {
            loggedInInstanceIDs.remove(instance.id)
        }
    }

    // MARK: - InstanceCredentialsManager Protocol

    /// Stores a credential (SID) for an Invidious instance.
    /// Protocol conformance - delegates to setSID.
    func setCredential(_ credential: String, for instance: Instance) {
        setSID(credential, for: instance)
    }

    /// Retrieves the stored credential (SID) for an Invidious instance.
    /// Protocol conformance - delegates to sid(for:).
    func credential(for instance: Instance) -> String? {
        sid(for: instance)
    }

    /// Deletes the stored credential (SID) for an Invidious instance.
    /// Protocol conformance - delegates to deleteSID.
    func deleteCredential(for instance: Instance) {
        deleteSID(for: instance)
    }
}
