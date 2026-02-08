//
//  YatteeServerCredentialsManager.swift
//  Yattee
//
//  Manages Yattee Server credentials (username/password) stored securely in the Keychain.
//

import Foundation
import Security

/// Credential structure for Yattee Server basic authentication.
struct YatteeServerCredential: Codable {
    let username: String
    let password: String
}

/// Manages Yattee Server credentials stored securely in the Keychain.
@MainActor
@Observable
final class YatteeServerCredentialsManager: InstanceCredentialsManager {
    private let keychainServiceName = "com.yattee.yatteeserver"

    /// Tracks which instances have stored credentials (for reactive UI updates)
    private(set) var loggedInInstanceIDs: Set<UUID> = []

    /// Reference to settings manager for iCloud sync decisions
    weak var settingsManager: SettingsManager?

    /// Whether credentials should sync to iCloud Keychain (when iCloud sync is enabled for instances).
    private var shouldSyncToiCloud: Bool {
        settingsManager?.iCloudSyncEnabled == true && settingsManager?.syncInstances == true
    }

    init() {}

    // MARK: - Public API

    /// Stores credentials for a Yattee Server instance.
    /// Credentials sync to iCloud Keychain when iCloud sync is enabled for instances.
    /// - Parameters:
    ///   - username: The username for basic auth
    ///   - password: The password for basic auth
    ///   - instance: The Yattee Server instance
    func setCredentials(username: String, password: String, for instance: Instance) {
        let account = instance.id.uuidString
        let credential = YatteeServerCredential(username: username, password: password)

        guard let data = try? JSONEncoder().encode(credential) else {
            LoggingService.shared.error("Failed to encode Yattee Server credentials", category: .keychain)
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
                "Stored credentials for Yattee Server instance",
                category: .keychain,
                details: "instanceID=\(instance.id), iCloudSync=\(syncEnabled)"
            )
            // Update tracked set for reactive UI
            loggedInInstanceIDs.insert(instance.id)
        } else {
            LoggingService.shared.error(
                "Failed to store credentials for Yattee Server instance",
                category: .keychain,
                details: "instanceID=\(instance.id), status=\(status)"
            )
        }
    }

    /// Retrieves credentials for a Yattee Server instance.
    /// Searches both synced and non-synced items.
    /// - Parameter instance: The Yattee Server instance
    /// - Returns: The credentials if stored, nil otherwise
    func credentials(for instance: Instance) -> YatteeServerCredential? {
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
              let credential = try? JSONDecoder().decode(YatteeServerCredential.self, from: data) else {
            LoggingService.shared.debug(
                "No credentials found for Yattee Server instance",
                category: .keychain,
                details: "instanceID=\(instance.id), status=\(status)"
            )
            return nil
        }

        LoggingService.shared.debug(
            "Retrieved credentials for Yattee Server instance",
            category: .keychain,
            details: "instanceID=\(instance.id)"
        )
        return credential
    }

    /// Deletes credentials for an instance.
    /// Deletes both synced and non-synced items.
    /// - Parameter instance: The Yattee Server instance
    func deleteCredentials(for instance: Instance) {
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
                "Deleted credentials for Yattee Server instance",
                category: .keychain,
                details: "instanceID=\(instance.id)"
            )
        } else {
            LoggingService.shared.error(
                "Failed to delete credentials for Yattee Server instance",
                category: .keychain,
                details: "instanceID=\(instance.id), status=\(status)"
            )
        }

        // Update tracked set for reactive UI
        loggedInInstanceIDs.remove(instance.id)
    }

    /// Checks if an instance has stored credentials.
    /// - Parameter instance: The Yattee Server instance
    /// - Returns: true if credentials exist, false otherwise
    func hasCredentials(for instance: Instance) -> Bool {
        // Check tracked set first for performance
        if loggedInInstanceIDs.contains(instance.id) {
            return true
        }
        // Fall back to Keychain check
        let hasCreds = credentials(for: instance) != nil
        if hasCreds {
            loggedInInstanceIDs.insert(instance.id)
        }
        return hasCreds
    }

    /// Refreshes the logged-in status for an instance.
    /// Call this when the view appears to ensure UI is in sync.
    func refreshLoginStatus(for instance: Instance) {
        if credentials(for: instance) != nil {
            loggedInInstanceIDs.insert(instance.id)
        } else {
            loggedInInstanceIDs.remove(instance.id)
        }
    }

    // MARK: - InstanceCredentialsManager Protocol

    /// Stores a credential for an instance (protocol conformance).
    /// The credential is expected to be a JSON-encoded YatteeServerCredential.
    /// - Parameters:
    ///   - credential: JSON string containing {"username": "...", "password": "..."}
    ///   - instance: The instance to associate the credential with
    func setCredential(_ credential: String, for instance: Instance) {
        guard let data = credential.data(using: .utf8),
              let creds = try? JSONDecoder().decode(YatteeServerCredential.self, from: data) else {
            LoggingService.shared.error(
                "Failed to decode credential string for Yattee Server",
                category: .keychain
            )
            return
        }
        setCredentials(username: creds.username, password: creds.password, for: instance)
    }

    /// Retrieves the stored credential for an instance (protocol conformance).
    /// Returns a JSON-encoded string of the username/password.
    /// - Parameter instance: The instance to retrieve the credential for
    /// - Returns: JSON string of the credential, or nil if not logged in
    func credential(for instance: Instance) -> String? {
        guard let creds = credentials(for: instance),
              let data = try? JSONEncoder().encode(creds),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }

    /// Deletes the stored credential for an instance (protocol conformance).
    /// - Parameter instance: The instance to log out from
    func deleteCredential(for instance: Instance) {
        deleteCredentials(for: instance)
    }

    /// Checks if an instance has a stored credential (protocol conformance).
    /// - Parameter instance: The instance to check
    /// - Returns: true if logged in, false otherwise
    func isLoggedIn(for instance: Instance) -> Bool {
        hasCredentials(for: instance)
    }

    // MARK: - Basic Auth Header Generation

    /// Generates the HTTP Basic Auth header value for an instance.
    /// - Parameter instance: The Yattee Server instance
    /// - Returns: The Authorization header value (e.g., "Basic dXNlcjpwYXNz") or nil if no credentials
    func basicAuthHeader(for instance: Instance) -> String? {
        guard let creds = credentials(for: instance) else { return nil }
        let credentials = "\(creds.username):\(creds.password)"
        guard let data = credentials.data(using: .utf8) else { return nil }
        return "Basic \(data.base64EncodedString())"
    }
}
