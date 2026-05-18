//
//  LegacyDataModels.swift
//  Yattee
//
//  Data models for parsing v1 UserDefaults format during migration.
//

import Foundation

// MARK: - Legacy Instance

/// Represents a v1 Instance stored in UserDefaults under the "instances" key.
/// The v1 format used Defaults.Serializable with a bridge that stored instances as [String: String] dictionaries.
struct LegacyInstance: Sendable {
    /// The app type: "invidious", "piped", "peerTube", "local"
    let app: String

    /// UUID string identifier
    let id: String

    /// User-defined name for the instance
    let name: String

    /// The API URL string (e.g., "https://invidious.example.com")
    let apiURL: String

    /// Optional frontend URL (used by Piped)
    let frontendURL: String?

    /// Whether the instance proxies videos
    let proxiesVideos: Bool

    /// Whether to use Invidious Companion
    let invidiousCompanion: Bool

    /// Parses a dictionary from v1 UserDefaults format.
    /// - Parameter dictionary: The serialized instance dictionary
    /// - Returns: A LegacyInstance if parsing succeeds, nil otherwise
    static func parse(from dictionary: [String: Any]) -> LegacyInstance? {
        guard let app = dictionary["app"] as? String,
              let id = dictionary["id"] as? String,
              let apiURL = dictionary["apiURL"] as? String else {
            return nil
        }

        let name = dictionary["name"] as? String ?? ""
        let frontendURL = dictionary["frontendURL"] as? String
        let proxiesVideos = (dictionary["proxiesVideos"] as? String) == "true"
        let invidiousCompanion = (dictionary["invidiousCompanion"] as? String) == "true"

        return LegacyInstance(
            app: app,
            id: id,
            name: name,
            apiURL: apiURL,
            frontendURL: frontendURL?.isEmpty == true ? nil : frontendURL,
            proxiesVideos: proxiesVideos,
            invidiousCompanion: invidiousCompanion
        )
    }

    /// Converts the legacy app type string to the v2 InstanceType.
    var instanceType: InstanceType? {
        switch app.lowercased() {
        case "invidious":
            return .invidious
        case "piped":
            return .piped
        case "peertube":
            return .peertube
        default:
            return nil
        }
    }

    /// The URL object for this instance.
    var url: URL? {
        URL(string: apiURL)
    }
}

// MARK: - Legacy Account

/// Represents a v1 account stored in UserDefaults under the "accounts" key.
/// Credentials moved between UserDefaults and the old Keychain across v1 releases,
/// so v2 only uses this metadata to help the user sign in again.
struct LegacyAccount: Sendable {
    /// Legacy account identifier, also used by v1 Keychain keys.
    let id: String

    /// Legacy instance identifier this account belonged to.
    let instanceID: String

    /// User-facing account name.
    let name: String

    /// The account/server URL string.
    let apiURL: String

    /// Stored username/email, when present in UserDefaults.
    let username: String

    /// Parses a dictionary from v1 UserDefaults format.
    /// - Parameter dictionary: The serialized account dictionary
    /// - Returns: A LegacyAccount if parsing succeeds, nil otherwise
    static func parse(from dictionary: [String: Any]) -> LegacyAccount? {
        guard let id = dictionary["id"] as? String,
              let apiURL = dictionary["apiURL"] as? String,
              let username = dictionary["username"] as? String else {
            return nil
        }

        let instanceID = dictionary["instanceID"] as? String ?? ""
        let name = dictionary["name"] as? String ?? ""

        return LegacyAccount(
            id: id,
            instanceID: instanceID,
            name: name,
            apiURL: apiURL,
            username: username
        )
    }
}

// MARK: - Legacy Account Import Item

/// Represents a legacy account that can be re-created by signing in to v2.
struct LegacyAccountImportItem: Identifiable, Sendable {
    /// The original v1 account ID.
    let legacyAccountID: String

    /// The original v1 instance ID.
    let legacyInstanceID: String

    /// The type of instance this account belongs to.
    let instanceType: InstanceType

    /// The instance URL.
    let url: URL

    /// User-defined instance name, if any.
    let instanceName: String?

    /// Legacy account display name, if any.
    let accountName: String?

    /// Legacy username/email.
    let username: String

    /// Whether this instance proxies videos.
    let proxiesVideos: Bool

    /// Stable identifier for SwiftUI lists.
    var id: String { legacyAccountID }

    /// Display name for the account row.
    var displayName: String {
        if let accountName, !accountName.isEmpty {
            return accountName
        }
        if !username.isEmpty {
            return username
        }
        return instanceDisplayName
    }

    /// Display name for the associated instance.
    var instanceDisplayName: String {
        if let instanceName, !instanceName.isEmpty {
            return instanceName
        }
        return url.host ?? url.absoluteString
    }
}

// MARK: - Legacy Instance Import Item

/// Represents a legacy instance (source) that can be re-created without signing in.
/// Used for v1 instances that have no associated account.
struct LegacyInstanceImportItem: Identifiable, Sendable {
    /// The original v1 instance ID.
    let legacyInstanceID: String

    /// The type of instance.
    let instanceType: InstanceType

    /// The instance URL.
    let url: URL

    /// User-defined instance name, if any.
    let instanceName: String?

    /// Whether this instance proxies videos.
    let proxiesVideos: Bool

    /// Stable identifier for SwiftUI lists.
    var id: String { legacyInstanceID }

    /// Display name for the source row.
    var instanceDisplayName: String {
        if let instanceName, !instanceName.isEmpty {
            return instanceName
        }
        return url.host ?? url.absoluteString
    }
}
