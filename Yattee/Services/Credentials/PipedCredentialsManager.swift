//
//  PipedCredentialsManager.swift
//  Yattee
//
//  Manages Piped authentication tokens stored securely in the Keychain.
//

import Foundation
import Security

/// Manages Piped auth tokens stored securely in the Keychain.
@MainActor
@Observable
final class PipedCredentialsManager: InstanceCredentialsManager {
    private let keychainServiceName = "com.yattee.piped"

    /// Tracks which instances have stored tokens (for reactive UI updates)
    private(set) var loggedInInstanceIDs: Set<UUID> = []

    /// Reference to settings manager for iCloud sync decisions
    weak var settingsManager: SettingsManager?

    /// Whether credentials should sync to iCloud Keychain (when iCloud sync is enabled for instances).
    private var shouldSyncToiCloud: Bool {
        settingsManager?.iCloudSyncEnabled == true && settingsManager?.syncInstances == true
    }

    // MARK: - InstanceCredentialsManager Protocol

    /// Stores the auth token for a Piped instance.
    /// Token syncs to iCloud Keychain when iCloud sync is enabled for instances.
    /// - Parameters:
    ///   - credential: The auth token from login
    ///   - instance: The Piped instance
    func setCredential(_ credential: String, for instance: Instance) {
        let account = instance.id.uuidString
        guard let data = credential.data(using: .utf8) else {
            LoggingService.shared.error("Failed to encode token data", category: .keychain)
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
                "Stored token for Piped instance",
                category: .keychain,
                details: "instanceID=\(instance.id), iCloudSync=\(syncEnabled)"
            )
            // Update tracked set for reactive UI
            loggedInInstanceIDs.insert(instance.id)
        } else {
            LoggingService.shared.error(
                "Failed to store token for Piped instance",
                category: .keychain,
                details: "instanceID=\(instance.id), status=\(status)"
            )
        }
    }

    /// Retrieves the auth token for a Piped instance.
    /// Searches both synced and non-synced items.
    /// - Parameter instance: The Piped instance
    /// - Returns: The auth token if stored, nil otherwise
    func credential(for instance: Instance) -> String? {
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
              let token = String(data: data, encoding: .utf8) else {
            LoggingService.shared.debug(
                "No token found for Piped instance",
                category: .keychain,
                details: "instanceID=\(instance.id), status=\(status)"
            )
            return nil
        }

        LoggingService.shared.debug(
            "Retrieved token for Piped instance",
            category: .keychain,
            details: "instanceID=\(instance.id)"
        )
        return token
    }

    /// Deletes the auth token for an instance (logout).
    /// Deletes both synced and non-synced items.
    /// - Parameter instance: The Piped instance
    func deleteCredential(for instance: Instance) {
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
                "Deleted token for Piped instance",
                category: .keychain,
                details: "instanceID=\(instance.id)"
            )
        } else {
            LoggingService.shared.error(
                "Failed to delete token for Piped instance",
                category: .keychain,
                details: "instanceID=\(instance.id), status=\(status)"
            )
        }

        // Update tracked set for reactive UI
        loggedInInstanceIDs.remove(instance.id)

        // Clear Feed cache on logout
        HomeInstanceCache.shared.clear(instanceID: instance.id, contentType: .feed)
    }

    /// Checks if an instance has a stored token.
    /// - Parameter instance: The Piped instance
    /// - Returns: true if logged in, false otherwise
    func isLoggedIn(for instance: Instance) -> Bool {
        // Check tracked set first for performance
        if loggedInInstanceIDs.contains(instance.id) {
            return true
        }
        // Fall back to Keychain check
        let hasToken = credential(for: instance) != nil
        if hasToken {
            loggedInInstanceIDs.insert(instance.id)
        }
        return hasToken
    }

    /// Refreshes the logged-in status for an instance.
    /// Call this when the view appears to ensure UI is in sync.
    func refreshLoginStatus(for instance: Instance) {
        if credential(for: instance) != nil {
            loggedInInstanceIDs.insert(instance.id)
        } else {
            loggedInInstanceIDs.remove(instance.id)
        }
    }
}
