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

    // MARK: - State

    /// Changes whenever legacy account or instance defaults are resolved, so SwiftUI views refresh.
    private(set) var legacyDataRevision = 0

    // MARK: - Initialization

    init(
        instancesManager: InstancesManager,
        basicAuthCredentialsManager: BasicAuthCredentialsManager,
        invidiousCredentialsManager: InvidiousCredentialsManager,
        pipedCredentialsManager: PipedCredentialsManager,
        invidiousAPI: InvidiousAPI,
        pipedAPI: PipedAPI
    ) {
        self.instancesManager = instancesManager
        self.basicAuthCredentialsManager = basicAuthCredentialsManager
        self.invidiousCredentialsManager = invidiousCredentialsManager
        self.pipedCredentialsManager = pipedCredentialsManager
        self.invidiousAPI = invidiousAPI
        self.pipedAPI = pipedAPI
    }

    // MARK: - Detection

    /// Whether there are legacy accounts left for the user to review.
    func hasLegacyAccountsToImport() -> Bool {
        _ = legacyDataRevision
        return !parseLegacyAccountsForImport().isEmpty
    }

    /// Whether there are account-less legacy instances (sources) left to import.
    func hasLegacyInstancesToImport() -> Bool {
        _ = legacyDataRevision
        return !parseLegacyInstancesForImport().isEmpty
    }

    /// Whether there is any legacy data (accounts or sources) left to import.
    func hasLegacyDataToImport() -> Bool {
        hasLegacyAccountsToImport() || hasLegacyInstancesToImport()
    }

    /// Whether the one-time legacy data prompt should be shown.
    var shouldShowLegacyAccountsPrompt: Bool {
        hasLegacyDataToImport() && !UserDefaults.standard.bool(forKey: legacyAccountsPromptShownKey)
    }

    /// Marks the one-time legacy account prompt as shown.
    func markLegacyAccountsPromptShown() {
        UserDefaults.standard.set(true, forKey: legacyAccountsPromptShownKey)
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

    /// Parses account-less legacy instances that can be re-added as sources.
    /// Instances tied to an account are handled by `parseLegacyAccountsForImport`
    /// and are omitted here; instances already present in v2 are omitted too.
    func parseLegacyInstancesForImport() -> [LegacyInstanceImportItem] {
        let defaults = UserDefaults.standard
        let legacyInstances = parseLegacyInstances(from: defaults)
        let accounts = parseLegacyAccounts(from: defaults)

        // Instances that already have an account are covered by the accounts section.
        let accountInstanceIDs = Set(accounts.map(\.instanceID))
        let accountHosts = Set(accounts.compactMap { account -> String? in
            guard let url = URL(string: account.apiURL) else { return nil }
            return Self.splitCredentials(from: url).cleanURL.host
        })

        return legacyInstances.compactMap { instance in
            guard let instanceType = instance.instanceType,
                  instanceType == .invidious || instanceType == .piped,
                  let url = instance.url
            else {
                return nil
            }

            if accountInstanceIDs.contains(instance.id) {
                return nil
            }

            let (cleanURL, _) = Self.splitCredentials(from: url)
            if let host = cleanURL.host, accountHosts.contains(host) {
                return nil
            }

            if isLegacyInstanceAlreadyImported(instanceType: instanceType, url: url) {
                return nil
            }

            return LegacyInstanceImportItem(
                legacyInstanceID: instance.id,
                instanceType: instanceType,
                url: url,
                instanceName: instance.name.isEmpty ? nil : instance.name,
                proxiesVideos: instance.proxiesVideos
            )
        }
    }

    // MARK: - Import

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

    /// Re-creates a legacy instance (source) without signing in.
    /// The matching source is created if needed; otherwise the existing one is reused.
    /// - Parameter item: The legacy instance to import
    /// - Returns: The instance that was created or reused
    @discardableResult
    func importLegacyInstance(_ item: LegacyInstanceImportItem) -> Instance {
        let (cleanURL, basicAuthCredentials) = Self.splitCredentials(from: item.url)

        let instance = instancesManager.instances.first { existing in
            existing.url.host == cleanURL.host && existing.type == item.instanceType
        } ?? Instance(
            id: UUID(),
            type: item.instanceType,
            url: cleanURL,
            name: item.instanceName,
            isEnabled: true,
            proxiesVideos: item.proxiesVideos
        )

        addInstanceIfNeeded(instance)

        if let basicAuthCredentials {
            basicAuthCredentialsManager.setCredentials(
                username: basicAuthCredentials.username,
                password: basicAuthCredentials.password,
                for: instance
            )
        }

        removeLegacyInstance(item)
        return instance
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

    private func isLegacyInstanceAlreadyImported(instanceType: InstanceType, url: URL) -> Bool {
        let (cleanURL, _) = Self.splitCredentials(from: url)
        return instancesManager.instances.contains { existing in
            existing.url.host == cleanURL.host && existing.type == instanceType
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

    // MARK: - Cleanup

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

        legacyDataRevision += 1
    }

    /// Removes one legacy instance after import or explicit user dismissal.
    /// If this was the last instance, the instance defaults key is removed.
    func removeLegacyInstance(_ item: LegacyInstanceImportItem) {
        removeLegacyInstances(withIDs: [item.legacyInstanceID])
    }

    private func removeLegacyInstances(withIDs ids: [String]) {
        let defaults = UserDefaults.standard
        let ids = Set(ids)

        guard var instances = defaults.array(forKey: legacyInstancesKey) as? [[String: Any]] else {
            return
        }

        let originalCount = instances.count
        instances.removeAll { dictionary in
            guard let instanceID = dictionary["id"] as? String else {
                return false
            }
            return ids.contains(instanceID)
        }

        guard instances.count != originalCount else {
            return
        }

        if instances.isEmpty {
            defaults.removeObject(forKey: legacyInstancesKey)
        } else {
            defaults.set(instances, forKey: legacyInstancesKey)
        }

        legacyDataRevision += 1
    }

    // MARK: - Prompt State

    private var legacyAccountsPromptShownKey: String {
        "legacyAccountsImportPromptShown_v1"
    }
}
