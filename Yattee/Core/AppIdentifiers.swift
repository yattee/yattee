import Foundation

/// Centralized app identifiers - single source of truth for all app-wide identifiers.
enum AppIdentifiers {
    // MARK: - Base Identifier

    static let bundleIdentifier = "stream.yattee.app"

    // MARK: - iCloud

    static var iCloudContainer: String {
        "iCloud.\(bundleIdentifier)"
    }

    // MARK: - Background Tasks

    static var backgroundFeedRefresh: String {
        "\(bundleIdentifier).feedRefresh"
    }

    // MARK: - User Activities (Handoff)

    static var handoffActivityType: String {
        "\(bundleIdentifier).activity"
    }

    // MARK: - URL Sessions

    static let downloadSession = "stream.yattee.downloads"

    // MARK: - Logging

    static var logSubsystem: String {
        bundleIdentifier
    }
}
