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

    /// Password value from very old defaults exports, if present.
    let password: String?

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
        let password = dictionary["password"] as? String

        return LegacyAccount(
            id: id,
            instanceID: instanceID,
            name: name,
            apiURL: apiURL,
            username: username,
            password: password?.isEmpty == true ? nil : password
        )
    }
}

// MARK: - Legacy Import Item

/// Represents an instance to be imported from v1 data.
/// Only instances are imported - users need to re-add their accounts after import.
struct LegacyImportItem: Identifiable, Sendable {
    /// New UUID for UI identification
    let id: UUID

    /// The original v1 instance ID
    let legacyInstanceID: String

    /// The type of instance (Invidious or Piped)
    let instanceType: InstanceType

    /// The instance URL
    let url: URL

    /// User-defined name for the instance
    let name: String?

    /// Whether this instance proxies videos
    var proxiesVideos: Bool = false

    /// Whether this item is selected for import
    var isSelected: Bool = true

    /// Current reachability status
    var reachabilityStatus: ReachabilityStatus = .unknown

    /// Display name for the UI
    var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        return url.host ?? url.absoluteString
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

// MARK: - Reachability Status

/// Status of an instance's reachability check.
enum ReachabilityStatus: Sendable {
    /// Not yet checked
    case unknown
    /// Currently checking
    case checking
    /// Instance is reachable
    case reachable
    /// Instance is unreachable
    case unreachable
}

// MARK: - Migration Result

/// Result of an import operation.
struct MigrationResult {
    /// Items that were successfully imported
    let succeeded: [LegacyImportItem]

    /// Items that failed to import with their errors
    let failed: [(item: LegacyImportItem, error: MigrationError)]

    /// Items that were skipped because they already exist
    let skippedDuplicates: [LegacyImportItem]

    /// Whether all selected items were successfully imported
    var isFullSuccess: Bool {
        failed.isEmpty
    }

    /// Total number of items processed
    var totalProcessed: Int {
        succeeded.count + failed.count + skippedDuplicates.count
    }
}

// MARK: - Migration Error

/// Errors that can occur during migration.
enum MigrationError: LocalizedError, Sendable {
    case invalidURL
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "migration.error.invalidURL")
        case .unknown(let message):
            return message
        }
    }
}
