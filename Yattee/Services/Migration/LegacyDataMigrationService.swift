//
//  LegacyDataMigrationService.swift
//  Yattee
//
//  Service for detecting, parsing, and importing v1 data during migration.
//

import Foundation

/// Service that handles migration of v1 Yattee data to the v2 format.
/// Detects legacy instances stored in UserDefaults and imports them into the new system.
/// Credentials are not imported - users need to sign in again after import.
@MainActor
@Observable
final class LegacyDataMigrationService {
    // MARK: - Constants

    /// UserDefaults key where v1 stored instances
    private let legacyInstancesKey = "instances"

    /// UserDefaults key where v1 stored accounts
    private let legacyAccountsKey = "accounts"

    // MARK: - Dependencies

    private let instancesManager: InstancesManager
    private let basicAuthCredentialsManager: BasicAuthCredentialsManager
    private let httpClient: HTTPClient

    // MARK: - State

    /// Whether an import is currently in progress
    private(set) var isImporting = false

    /// Progress of the current import (0.0 to 1.0)
    private(set) var importProgress: Double = 0.0

    // MARK: - Initialization

    init(
        instancesManager: InstancesManager,
        basicAuthCredentialsManager: BasicAuthCredentialsManager,
        httpClient: HTTPClient = HTTPClient()
    ) {
        self.instancesManager = instancesManager
        self.basicAuthCredentialsManager = basicAuthCredentialsManager
        self.httpClient = httpClient
    }

    // MARK: - Detection

    /// Checks if there is legacy v1 data available for migration.
    /// - Returns: true if v1 data exists and can be parsed
    func hasLegacyData() -> Bool {
        guard let items = parseLegacyData() else { return false }
        return !items.isEmpty
    }

    /// Parses legacy v1 data from UserDefaults.
    /// - Returns: Array of import items, or nil if data is corrupted or doesn't exist
    func parseLegacyData() -> [LegacyImportItem]? {
        let defaults = UserDefaults.standard

        // Check if legacy data exists
        guard defaults.object(forKey: legacyInstancesKey) != nil ||
              defaults.object(forKey: legacyAccountsKey) != nil else {
            return nil
        }

        // Parse instances only (credentials are not imported)
        let legacyInstances = parseLegacyInstances(from: defaults)

        // Build import items - one per unique instance
        var items: [LegacyImportItem] = []

        for instance in legacyInstances {
            // Skip PeerTube (not supported in migration)
            guard let instanceType = instance.instanceType,
                  instanceType != .peertube else {
                continue
            }

            guard let url = instance.url else { continue }

            let item = LegacyImportItem(
                id: UUID(),
                legacyInstanceID: instance.id,
                instanceType: instanceType,
                url: url,
                name: instance.name.isEmpty ? nil : instance.name,
                proxiesVideos: instance.proxiesVideos
            )
            items.append(item)
        }

        // Return nil if no valid items were found (treat as no data)
        return items.isEmpty ? nil : items
    }

    // MARK: - Parsing Helpers

    private func parseLegacyInstances(from defaults: UserDefaults) -> [LegacyInstance] {
        // v1 used Defaults library which stores arrays of dictionaries
        guard let array = defaults.array(forKey: legacyInstancesKey) as? [[String: Any]] else {
            return []
        }

        return array.compactMap { LegacyInstance.parse(from: $0) }
    }

    // MARK: - Reachability

    /// Checks if an instance is reachable.
    /// - Parameter item: The import item to check
    /// - Returns: true if the instance responds, false otherwise
    func checkReachability(for item: LegacyImportItem) async -> Bool {
        // Build the appropriate health check endpoint based on instance type
        let endpoint: GenericEndpoint
        switch item.instanceType {
        case .invidious:
            endpoint = GenericEndpoint(path: "/api/v1/stats", timeout: 10)
        case .piped:
            endpoint = GenericEndpoint(path: "/healthcheck", timeout: 10)
        default:
            return false
        }

        do {
            _ = try await httpClient.fetchData(endpoint, baseURL: item.url)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Import

    /// Imports the selected items into the v2 system.
    /// - Parameter items: The items to import (only selected items will be processed)
    /// - Returns: The result of the import operation
    func importItems(_ items: [LegacyImportItem]) async -> MigrationResult {
        isImporting = true
        importProgress = 0.0

        let selectedItems = items.filter(\.isSelected)
        var succeeded: [LegacyImportItem] = []
        var failed: [(item: LegacyImportItem, error: MigrationError)] = []
        var skippedDuplicates: [LegacyImportItem] = []

        let total = selectedItems.count

        for (index, item) in selectedItems.enumerated() {
            // Update progress
            importProgress = Double(index) / Double(max(total, 1))

            // Check for duplicates
            if isDuplicate(item) {
                skippedDuplicates.append(item)
                continue
            }

            // Perform import
            do {
                try importItem(item)
                succeeded.append(item)
            } catch let error as MigrationError {
                failed.append((item, error))
            } catch {
                failed.append((item, .unknown(error.localizedDescription)))
            }
        }

        importProgress = 1.0
        isImporting = false

        return MigrationResult(
            succeeded: succeeded,
            failed: failed,
            skippedDuplicates: skippedDuplicates
        )
    }

    /// Imports a single item into the v2 system.
    /// If the legacy URL contains embedded basic-auth credentials
    /// (e.g. `https://user:pass@host`), they are stripped from the URL
    /// and stored in the Keychain via `BasicAuthCredentialsManager`.
    private func importItem(_ item: LegacyImportItem) throws {
        let (cleanURL, credentials) = Self.splitCredentials(from: item.url)

        let instance = Instance(
            id: UUID(),
            type: item.instanceType,
            url: cleanURL,
            name: item.name,
            isEnabled: true,
            proxiesVideos: item.proxiesVideos
        )

        instancesManager.add(instance)

        if let credentials {
            basicAuthCredentialsManager.setCredentials(
                username: credentials.username,
                password: credentials.password,
                for: instance
            )
        }
    }

    /// Checks if an import item would be a duplicate of an existing instance.
    private func isDuplicate(_ item: LegacyImportItem) -> Bool {
        let (cleanURL, _) = Self.splitCredentials(from: item.url)
        for existing in instancesManager.instances {
            if existing.url.host == cleanURL.host && existing.type == item.instanceType {
                return true
            }
        }
        return false
    }

    // MARK: - Credential Splitting

    /// Splits embedded basic-auth credentials out of a URL.
    /// v1 supported credentials embedded directly in the URL (e.g. `https://user:pass@host`);
    /// v2 stores them separately in the Keychain.
    /// - Returns: The cleaned URL (no user/password) and the extracted credentials, if any.
    static func splitCredentials(from url: URL) -> (cleanURL: URL, credentials: BasicAuthCredential?) {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let user = components.user, !user.isEmpty else {
            return (url, nil)
        }

        let password = components.password ?? ""
        components.user = nil
        components.password = nil

        let cleaned = components.url ?? url
        return (cleaned, BasicAuthCredential(username: user, password: password))
    }

    // MARK: - Auto-Import

    /// Silently imports any legacy v1 data on first launch.
    /// Skips unreachable-checks and UI; just imports everything and deletes the legacy keys.
    /// Safe to call repeatedly — if there is no legacy data left, this is a no-op.
    func autoImportIfNeeded() async {
        guard let items = parseLegacyData() else { return }
        _ = await importItems(items)
        deleteLegacyData()
    }

    // MARK: - Cleanup

    /// Deletes the legacy v1 data from UserDefaults.
    /// Call this after a successful import or when the user confirms they don't want to import.
    func deleteLegacyData() {
        let defaults = UserDefaults.standard

        // Remove legacy keys
        defaults.removeObject(forKey: legacyInstancesKey)
        defaults.removeObject(forKey: legacyAccountsKey)

        // Note: We don't delete the old Keychain items as they may be needed
        // if the user reinstalls v1 or for debugging purposes.
        // The old Keychain service name is different so there's no conflict.
    }
}
