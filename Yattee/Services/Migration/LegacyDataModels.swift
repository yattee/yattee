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
struct LegacyInstance {
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
