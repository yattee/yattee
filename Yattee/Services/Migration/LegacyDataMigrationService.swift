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
    private let invidiousCredentialsManager: InvidiousCredentialsManager
    private let pipedCredentialsManager: PipedCredentialsManager
    private let invidiousAPI: InvidiousAPI
    private let pipedAPI: PipedAPI
    private let httpClient: HTTPClient

    // MARK: - State

    /// Whether an import is currently in progress
    private(set) var isImporting = false

    /// Progress of the current import (0.0 to 1.0)
    private(set) var importProgress: Double = 0.0

    /// Changes whenever legacy account defaults are resolved, so SwiftUI views refresh.
    private(set) var legacyAccountsRevision = 0

    // MARK: - Initialization

    init(
        instancesManager: InstancesManager,
        basicAuthCredentialsManager: BasicAuthCredentialsManager,
        invidiousCredentialsManager: InvidiousCredentialsManager,
        pipedCredentialsManager: PipedCredentialsManager,
        invidiousAPI: InvidiousAPI,
        pipedAPI: PipedAPI,
        httpClient: HTTPClient = HTTPClient()
    ) {
        self.instancesManager = instancesManager
        self.basicAuthCredentialsManager = basicAuthCredentialsManager
        self.invidiousCredentialsManager = invidiousCredentialsManager
        self.pipedCredentialsManager = pipedCredentialsManager
        self.invidiousAPI = invidiousAPI
        self.pipedAPI = pipedAPI
        self.httpClient = httpClient
    }

    // MARK: - Detection

    /// Checks if there is legacy v1 data available for migration.
    /// - Returns: true if v1 data exists and can be parsed
    func hasLegacyData() -> Bool {
        guard let items = parseLegacyData() else { return false }
        return !items.isEmpty
    }

    /// Whether there are legacy accounts left for the user to review.
    func hasLegacyAccountsToImport() -> Bool {
        _ = legacyAccountsRevision
        return !parseLegacyAccountsForImport().isEmpty
    }

    /// Whether the one-time legacy account prompt should be shown.
    var shouldShowLegacyAccountsPrompt: Bool {
        hasLegacyAccountsToImport() && !UserDefaults.standard.bool(forKey: legacyAccountsPromptShownKey)
    }

    /// Marks the one-time legacy account prompt as shown.
    func markLegacyAccountsPromptShown() {
        UserDefaults.standard.set(true, forKey: legacyAccountsPromptShownKey)
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

    private func parseLegacyAccounts(from defaults: UserDefaults) -> [LegacyAccount] {
        guard let array = defaults.array(forKey: legacyAccountsKey) as? [[String: Any]] else {
            return []
        }

        return array.compactMap { LegacyAccount.parse(from: $0) }
    }

    /// Parses legacy accounts and matches them with their legacy instances.
    /// Accounts without a supported Invidious/Piped instance are omitted.
    func parseLegacyAccountsForImport() -> [LegacyAccountImportItem] {
        let defaults = UserDefaults.standard
        let legacyInstances = parseLegacyInstances(from: defaults)
        let instancesByID = legacyInstances.reduce(into: [String: LegacyInstance]()) { result, instance in
            result[instance.id] = instance
        }
        let accounts = parseLegacyAccounts(from: defaults)

        let importItems: [LegacyAccountImportItem] = accounts.compactMap { account in
            let matchedInstance = instancesByID[account.instanceID]
                ?? legacyInstances.first { $0.apiURL == account.apiURL }

            guard let instance = matchedInstance,
                  let instanceType = instance.instanceType,
                  instanceType == .invidious || instanceType == .piped,
                  let url = instance.url ?? URL(string: account.apiURL)
            else {
                return nil
            }

            if isLegacyAccountAlreadyImported(instanceType: instanceType, url: url) {
                return nil
            }

            return LegacyAccountImportItem(
                legacyAccountID: account.id,
                legacyInstanceID: instance.id,
                instanceType: instanceType,
                url: url,
                instanceName: instance.name.isEmpty ? nil : instance.name,
                accountName: account.name.isEmpty ? nil : account.name,
                username: account.username,
                proxiesVideos: instance.proxiesVideos
            )
        }

        return importItems
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

    /// Re-creates a legacy account by signing in with fresh credentials.
    /// The matching source is created if needed; otherwise the existing matching source is reused.
    /// - Parameters:
    ///   - item: The legacy account to import
    ///   - username: Username/email to use for the v2 login
    ///   - password: Password to use for the v2 login
    /// - Returns: The instance that now has the imported login credential
    @discardableResult
    func importLegacyAccount(_ item: LegacyAccountImportItem, username: String, password: String) async throws -> Instance {
        let instance = instanceForAccountImport(item)
        let (_, basicAuthCredentials) = Self.splitCredentials(from: item.url)

        let credential: String
        switch item.instanceType {
        case .invidious:
            let extraHeaders = basicAuthCredentials.map {
                ["Authorization": Self.basicAuthHeader(username: $0.username, password: $0.password)]
            }
            credential = try await invidiousAPI.login(
                email: username,
                password: password,
                instance: instance,
                extraHeaders: extraHeaders
            )
            addInstanceIfNeeded(instance)
            if let basicAuthCredentials {
                basicAuthCredentialsManager.setCredentials(
                    username: basicAuthCredentials.username,
                    password: basicAuthCredentials.password,
                    for: instance
                )
            }
            invidiousCredentialsManager.setCredential(credential, for: instance)

        case .piped:
            credential = try await pipedAPI.login(username: username, password: password, instance: instance)
            addInstanceIfNeeded(instance)
            pipedCredentialsManager.setCredential(credential, for: instance)

        default:
            throw APIError.notSupported
        }

        removeLegacyAccount(item)
        return instance
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

    private func instanceForAccountImport(_ item: LegacyAccountImportItem) -> Instance {
        let (cleanURL, _) = Self.splitCredentials(from: item.url)
        if let existing = instancesManager.instances.first(where: { existing in
            existing.url.host == cleanURL.host && existing.type == item.instanceType
        }) {
            return existing
        }

        return Instance(
            id: UUID(),
            type: item.instanceType,
            url: cleanURL,
            name: item.instanceName,
            isEnabled: true,
            proxiesVideos: item.proxiesVideos
        )
    }

    private func addInstanceIfNeeded(_ instance: Instance) {
        guard !instancesManager.instances.contains(where: { $0.id == instance.id }) else {
            return
        }

        instancesManager.add(instance)
    }

    private func isLegacyAccountAlreadyImported(instanceType: InstanceType, url: URL) -> Bool {
        let (cleanURL, _) = Self.splitCredentials(from: url)

        guard let existingInstance = instancesManager.instances.first(where: { existing in
            existing.url.host == cleanURL.host && existing.type == instanceType
        }) else {
            return false
        }

        switch instanceType {
        case .invidious:
            return invidiousCredentialsManager.isLoggedIn(for: existingInstance)
        case .piped:
            return pipedCredentialsManager.isLoggedIn(for: existingInstance)
        default:
            return false
        }
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

    private static func basicAuthHeader(username: String, password: String) -> String {
        let value = "\(username):\(password)"
        let encoded = Data(value.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    // MARK: - Auto-Import

    /// Silently imports any legacy v1 data on first launch.
    /// Skips unreachable-checks and UI; just imports everything and deletes the legacy keys.
    /// Safe to call repeatedly — if there is no legacy data left, this is a no-op.
    func autoImportIfNeeded() async {
        // Silent migration is intentionally disabled. Legacy accounts require
        // explicit review because v2 stores fresh per-instance session tokens.
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

    /// Removes one legacy account after successful import or explicit user dismissal.
    /// If this was the last account, the account defaults key is removed.
    func removeLegacyAccount(_ item: LegacyAccountImportItem) {
        removeLegacyAccounts(withIDs: [item.legacyAccountID])
    }

    private func removeLegacyAccounts(withIDs ids: [String]) {
        let defaults = UserDefaults.standard
        let ids = Set(ids)

        guard var accounts = defaults.array(forKey: legacyAccountsKey) as? [[String: Any]] else {
            return
        }

        let originalCount = accounts.count
        accounts.removeAll { dictionary in
            guard let accountID = dictionary["id"] as? String else {
                return false
            }
            return ids.contains(accountID)
        }

        guard accounts.count != originalCount else {
            return
        }

        if accounts.isEmpty {
            defaults.removeObject(forKey: legacyAccountsKey)
        } else {
            defaults.set(accounts, forKey: legacyAccountsKey)
        }

        legacyAccountsRevision += 1
    }

    // MARK: - Prompt State

    private var legacyAccountsPromptShownKey: String {
        "legacyAccountsImportPromptShown_v1"
    }
}
