//
//  AccountsManager.swift
//  Yattee
//
//  Owns the set of configured accounts and the currently selected data context.
//

import Foundation

/// Why an account cannot currently be used.
enum AccountStatus: Hashable, Sendable {
    /// Signed in and usable.
    case signedIn
    /// No credential on this device. On tvOS this is permanent until the user
    /// signs in locally — Apple never syncs app Keychain items there — so it
    /// must not be presented as a sync that is still in progress.
    case credentialMissing
    /// The server rejected the credential. Account-scoped: a rejected login on
    /// one account never disables the instance or its sibling accounts.
    case credentialRejected
    /// The server could not be reached. Never invalidates a credential.
    case unreachable
}

/// Owns accounts and the selected `DataContext`.
///
/// Storage is UserDefaults, namespaced by the credential identity scope so the
/// previous Apple account's account list is never displayed under a new one.
/// The dirty-flag outbox records what still needs uploading; CloudKit sync
/// attaches to it rather than being the source of truth for reads, so the app
/// works fully offline and in sideloaded builds where CloudKit is unavailable.
@MainActor
@Observable
final class AccountsManager {
    // MARK: - Storage

    private let defaults: UserDefaults
    private let identityScope: CredentialIdentityScope
    private weak var instancesManager: InstancesManager?

    // MARK: - State

    private(set) var accounts: [Account] = []
    private(set) var accountStatuses: [UUID: AccountStatus] = [:]

    /// The user's selected context, as persisted. Never silently corrected —
    /// see `DataContextValidator` for the rules that may change it.
    private(set) var storedContext = StoredDataContext(context: .local)

    /// Instances whose legacy single-login has already been turned into an
    /// account. Permanent: `usesAccountLogin` stays true on the instance
    /// forever, so the marker — not the account's existence — is what stops a
    /// deliberately deleted account from being recreated on next launch.
    private(set) var migratedInstanceIDs: Set<UUID> = []

    /// Records that still need uploading, so a change made offline or lost to a
    /// crash before the sync engine registered it is replayed on next launch.
    private(set) var pendingUploads: Set<UUID> = []
    private(set) var pendingDeletions: Set<UUID> = []

    var currentContext: DataContext { storedContext.context }

    // MARK: - Initialization

    init(
        identityScope: CredentialIdentityScope,
        instancesManager: InstancesManager? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.identityScope = identityScope
        self.instancesManager = instancesManager
        self.defaults = defaults

        load()

        // A change of Apple Account changes which namespace this manager reads,
        // so everything held in memory belongs to the previous one.
        NotificationCenter.default.addObserver(
            forName: .credentialIdentityScopeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadForCurrentIdentity() }
        }

        NotificationCenter.default.addObserver(
            forName: .instancesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Instances arrive from iCloud on their own timeline, so
                // migration is a repeatable reconciliation rather than a
                // one-shot at launch: a legacy instance can show up minutes in.
                self?.reconcileLegacyAccounts()
            }
        }
    }

    func setInstancesManager(_ manager: InstancesManager) {
        instancesManager = manager
        reconcileLegacyAccounts()
    }

    // MARK: - Lookup

    func account(id: UUID) -> Account? {
        accounts.first { $0.id == id }
    }

    func accounts(forInstance instanceID: UUID) -> [Account] {
        accounts.filter { $0.instanceID == instanceID }
    }

    /// The instance an account lives on, or `nil` when it hasn't arrived yet
    /// (or was deleted, leaving the account orphaned).
    func instance(for account: Account) -> Instance? {
        instancesManager?.instances.first { $0.id == account.instanceID }
    }

    /// What this account can do, resolved through its instance.
    ///
    /// `nil` when the instance is unknown — an account whose instance hasn't
    /// synced yet has no *known* capabilities, which is different from having
    /// none, and callers must not treat it as a usable context.
    func capabilities(for account: Account) -> AccountCapabilities? {
        instance(for: account)?.type.accountCapabilities
    }

    /// Accounts that can be selected as the current context right now.
    ///
    /// Excludes accounts still waiting for their instance: showing a context
    /// the app cannot actually resolve would be a dead end.
    var selectableAccounts: [Account] {
        accounts.filter { capabilities(for: $0)?.isSelectableContext == true }
    }

    /// Accounts whose instance is gone. Surfaced in the accounts screen with a
    /// remove action rather than being deleted automatically — an instance can
    /// be missing because iCloud hasn't delivered it yet.
    var orphanedAccounts: [Account] {
        accounts.filter { instance(for: $0) == nil }
    }

    // MARK: - Mutation

    @discardableResult
    func addAccount(instanceID: UUID, displayName: String? = nil) -> Account {
        let account = Account(instanceID: instanceID, displayName: displayName)
        accounts.append(account)
        pendingUploads.insert(account.id)

        // Signing in marks the instance migrated. Creating an account flips
        // `usesAccountLogin`, which posts instancesDidChange and re-runs
        // reconciliation immediately — without this the reconciliation would
        // synthesize a second, credential-less account for the same instance.
        migratedInstanceIDs.insert(instanceID)

        save()
        return account
    }

    func updateDisplayName(_ displayName: String?, for accountID: UUID) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[index].displayName = displayName
        accounts[index].updatedAt = Date()
        pendingUploads.insert(accountID)
        save()
    }

    /// Removes an account and everything keyed to it.
    ///
    /// The deletion is recorded in the outbox before anything else so that a
    /// crash mid-way still replays it — and so a peer that recreates the
    /// account from a stale queued edit is corrected rather than obeyed.
    func removeAccount(_ accountID: UUID) {
        guard let account = account(id: accountID) else { return }

        accounts.removeAll { $0.id == accountID }
        accountStatuses[accountID] = nil
        pendingUploads.remove(accountID)
        pendingDeletions.insert(accountID)

        // Selecting a deleted account would leave the UI pointing at nothing.
        // This is an explicit local deletion, which is one of the few things
        // allowed to correct the context.
        if storedContext.context == .account(accountID) {
            setContext(.local)
        }

        save()

        NotificationCenter.default.post(name: .accountsDidChange, object: nil)
        _ = account
    }

    /// Marks a deletion as confirmed by the server. Until then it stays in the
    /// outbox and is retried, because a tombstone that never lands lets a stale
    /// device resurrect the account.
    func confirmDeletion(_ accountID: UUID) {
        pendingDeletions.remove(accountID)
        save()
    }

    func confirmUpload(_ accountID: UUID) {
        pendingUploads.remove(accountID)
        save()
    }

    // MARK: - Context

    /// Records an explicit user choice of context.
    func setContext(_ context: DataContext) {
        storedContext = StoredDataContext(context: context)
        hasStoredContext = true
        save()
        NotificationCenter.default.post(name: .dataContextDidChange, object: nil)
    }

    /// Applies a context that arrived from another device, honouring the
    /// app-managed timestamp: an older value never overwrites a newer one, so a
    /// migration write can't undo a deliberate choice made elsewhere.
    func applySyncedContext(_ incoming: StoredDataContext) {
        guard incoming.changedAt > storedContext.changedAt else { return }
        storedContext = incoming
        hasStoredContext = true
        save()
        NotificationCenter.default.post(name: .dataContextDidChange, object: nil)
    }

    // MARK: - Status

    func setStatus(_ status: AccountStatus, for accountID: UUID) {
        guard accountStatuses[accountID] != status else { return }
        accountStatuses[accountID] = status
        NotificationCenter.default.post(name: .accountsDidChange, object: nil)
    }

    func status(for accountID: UUID) -> AccountStatus {
        accountStatuses[accountID] ?? .credentialMissing
    }

    // MARK: - Legacy migration

    /// Turns each pre-revamp single-login instance into an account.
    ///
    /// Repeatable by design: instances arrive over iCloud whenever they arrive,
    /// so this runs on every `instancesDidChange` rather than once at launch.
    /// The marker set is what makes re-running safe — without it, deleting a
    /// migrated account would simply recreate it, because `usesAccountLogin`
    /// remains true on the instance forever.
    func reconcileLegacyAccounts() {
        guard let instancesManager else { return }

        var didChange = false

        for instance in instancesManager.instances {
            guard instance.usesAccountLogin else { continue }
            guard instance.type.accountCapabilities.isSelectableContext else { continue }
            guard !migratedInstanceIDs.contains(instance.id) else { continue }

            // Any account on this instance means its login is already
            // represented — whether by an earlier migration or by a fresh
            // sign-in. Synthesizing beside it would leave a credential-less
            // duplicate.
            guard accounts(forInstance: instance.id).isEmpty else {
                migratedInstanceIDs.insert(instance.id)
                didChange = true
                continue
            }

            migratedInstanceIDs.insert(instance.id)
            didChange = true

            let account = Account.migrated(from: instance.id, dateAdded: instance.dateAdded)
            accounts.append(account)
            pendingUploads.insert(account.id)

            LoggingService.shared.info(
                "Migrated a legacy instance login into an account",
                category: .general,
                details: "instanceID=\(instance.id)"
            )
        }

        if didChange {
            save()
            migrateLegacyContextIfNeeded()
            NotificationCenter.default.post(name: .accountsDidChange, object: nil)
        }
    }

    /// One-way migration of the legacy `subscriptionAccount` selection.
    ///
    /// Runs only while no context has ever been chosen. The legacy value is read
    /// from local defaults first and then from the raw KVS value, because the
    /// previous release wrote the key to iCloud but never imported it back — on
    /// a fresh install the only copy lives in KVS.
    func migrateLegacyContextIfNeeded() {
        guard !hasStoredContext else { return }

        guard let legacy = legacySubscriptionAccount() else { return }

        let context = DataContext(legacy: legacy)

        // Only adopt a context whose account actually exists; otherwise the app
        // would start up pointing at something it cannot resolve.
        if case let .account(id) = context, account(id: id) == nil { return }

        storedContext = .migrated(context)
        hasStoredContext = true
        save()

        LoggingService.shared.info(
            "Migrated the legacy subscription account into a data context",
            category: .general
        )
    }

    private func legacySubscriptionAccount() -> SubscriptionAccount? {
        let key = "subscriptionAccount"

        if let data = defaults.data(forKey: key),
           let value = try? JSONDecoder().decode(SubscriptionAccount.self, from: data) {
            return value
        }

        // The previous release published this to iCloud but never read it back,
        // so a fresh install can hold the legacy selection only here.
        if let data = NSUbiquitousKeyValueStore.default.data(forKey: key),
           let value = try? JSONDecoder().decode(SubscriptionAccount.self, from: data) {
            return value
        }

        return nil
    }

    // MARK: - Persistence

    /// Storage keys are namespaced by identity so a switch of Apple account
    /// cannot show — or upload — the previous one's accounts. An unresolved
    /// scope falls back to a namespace of its own rather than sharing one.
    private var namespace: String {
        identityScope.current ?? "unresolved"
    }

    private func key(_ name: String) -> String {
        "accounts.\(namespace).\(name)"
    }

    private var hasStoredContext: Bool {
        get { defaults.bool(forKey: key("hasContext")) }
        set { defaults.set(newValue, forKey: key("hasContext")) }
    }

    private func load() {
        if let data = defaults.data(forKey: key("accounts")),
           let decoded = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = decoded
        }

        if let data = defaults.data(forKey: key("context")),
           let decoded = try? JSONDecoder().decode(StoredDataContext.self, from: data) {
            storedContext = decoded
        }

        if let ids = defaults.array(forKey: key("migrated")) as? [String] {
            migratedInstanceIDs = Set(ids.compactMap(UUID.init(uuidString:)))
        }

        if let ids = defaults.array(forKey: key("pendingUploads")) as? [String] {
            pendingUploads = Set(ids.compactMap(UUID.init(uuidString:)))
        }

        if let ids = defaults.array(forKey: key("pendingDeletions")) as? [String] {
            pendingDeletions = Set(ids.compactMap(UUID.init(uuidString:)))
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: key("accounts"))
        }
        if let data = try? JSONEncoder().encode(storedContext) {
            defaults.set(data, forKey: key("context"))
        }
        defaults.set(migratedInstanceIDs.map(\.uuidString), forKey: key("migrated"))
        defaults.set(pendingUploads.map(\.uuidString), forKey: key("pendingUploads"))
        defaults.set(pendingDeletions.map(\.uuidString), forKey: key("pendingDeletions"))
    }

    /// Re-reads storage under the current identity namespace.
    ///
    /// Called when the credential scope resolves or changes: the accounts held
    /// in memory belong to whichever namespace was active when they were loaded.
    func reloadForCurrentIdentity() {
        accounts = []
        accountStatuses = [:]
        storedContext = StoredDataContext(context: .local)
        migratedInstanceIDs = []
        pendingUploads = []
        pendingDeletions = []

        load()
        reconcileLegacyAccounts()

        NotificationCenter.default.post(name: .accountsDidChange, object: nil)
    }
}

extension Notification.Name {
    static let accountsDidChange = Notification.Name("stream.yattee.accountsDidChange")
    static let dataContextDidChange = Notification.Name("stream.yattee.dataContextDidChange")
}
