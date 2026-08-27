//
//  AccountsManager.swift
//  Yattee
//
//  Owns the set of configured accounts and the currently selected data context.
//

import Foundation

/// Why an account cannot currently be used.
enum AccountStatus: Hashable, Sendable {
    /// Nothing is known yet — the Apple account this device's credentials are
    /// keyed by has not been established, so the Keychain cannot be read under
    /// the right scope. Distinct from `credentialMissing`, which is an answer:
    /// this one is the absence of one, and must never be presented as "signed
    /// out" or acted on.
    case checking
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

    /// Instances whose migration marker still has to reach the server.
    ///
    /// Tracked apart from `migratedInstanceIDs` because the marker is held back
    /// until the account it describes is confirmed: a marker that outran a
    /// silently failed account save would suppress synthesis everywhere for an
    /// account no device has.
    private(set) var pendingMarkerUploads: Set<UUID> = []

    /// Whether the selected context still has to reach the server.
    private(set) var pendingContextUpload = false

    /// Accounts known to be deleted. Permanent, and the only thing that
    /// authorises removing an account that arrives from sync: a record's
    /// *absence* proves nothing, because a fetch resumes from a change token
    /// rather than enumerating the zone.
    private(set) var deletedAccountIDs: Set<UUID> = []

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
        markMigrated(instanceID)

        save()
        NotificationCenter.default.post(name: .accountsDidChange, object: nil)
        return account
    }

    /// Records that this instance's legacy login is now represented by an
    /// account, and that the fact has to be published.
    ///
    /// Publishing matters even when the account was created by a fresh sign-in
    /// rather than by synthesis: without the marker, every other device would
    /// still synthesize its own credential-less account for the same instance.
    private func markMigrated(_ instanceID: UUID) {
        guard !migratedInstanceIDs.contains(instanceID) else { return }
        migratedInstanceIDs.insert(instanceID)
        pendingMarkerUploads.insert(instanceID)
    }

    func updateDisplayName(_ displayName: String?, for accountID: UUID) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[index].displayName = displayName
        accounts[index].updatedAt = Date()
        pendingUploads.insert(accountID)
        save()
        NotificationCenter.default.post(name: .accountsDidChange, object: nil)
    }

    /// Removes an account and everything keyed to it.
    ///
    /// The deletion is recorded in the outbox before anything else so that a
    /// crash mid-way still replays it — and so a peer that recreates the
    /// account from a stale queued edit is corrected rather than obeyed.
    func removeAccount(_ accountID: UUID) {
        guard account(id: accountID) != nil else { return }

        // Queued before anything else can persist: a crash in between would
        // otherwise leave the account deleted here with no tombstone owed to
        // the server, and every other device would keep — or recreate — it.
        pendingDeletions.insert(accountID)
        forgetAccount(accountID)

        save()

        NotificationCenter.default.post(name: .accountsDidChange, object: nil)
    }

    /// Undoes an account that was created moments ago and could not be
    /// completed — a sign-in whose credential the Keychain refused to store.
    ///
    /// Not the same as deleting it. Creating an account also marks its instance
    /// migrated and queues the permanent marker that stops every other device
    /// from synthesizing an account for that instance's pre-revamp login. A
    /// deletion is meant to leave that marker standing; a creation that never
    /// happened must not, or a legacy login that is still perfectly valid would
    /// be suppressed everywhere on the strength of an account nobody has.
    func rollbackAccountCreation(_ accountID: UUID) {
        guard let account = account(id: accountID) else { return }

        // Confirmed by the server already? Then it is a real account elsewhere,
        // and undoing it means a real deletion, tombstone and all.
        guard pendingUploads.contains(accountID) else {
            removeAccount(accountID)
            return
        }

        accounts.removeAll { $0.id == accountID }
        accountStatuses[accountID] = nil
        pendingUploads.remove(accountID)

        // Retracted only while the marker is still ours to retract: never
        // confirmed by the server, and nothing else on the instance relying on
        // it. A tombstone for the migrated account keeps synthesis suppressed
        // on its own, so nothing is resurrected by this.
        if pendingMarkerUploads.contains(account.instanceID),
           accounts(forInstance: account.instanceID).isEmpty {
            pendingMarkerUploads.remove(account.instanceID)
            migratedInstanceIDs.remove(account.instanceID)
        }

        if storedContext.context == .account(accountID) {
            correctContextAfterDeletion()
        }

        save()
        NotificationCenter.default.post(name: .accountsDidChange, object: nil)
    }

    /// Drops an account and everything keyed to it, and records the permanent
    /// local tombstone.
    ///
    /// Shared by explicit local deletion and by deletions arriving from sync, so
    /// that both leave exactly the same state behind — including the tombstone,
    /// which is what stops a stale device's queued edit from resurrecting the
    /// account here.
    private func forgetAccount(_ accountID: UUID) {
        accounts.removeAll { $0.id == accountID }
        accountStatuses[accountID] = nil
        pendingUploads.remove(accountID)
        deletedAccountIDs.insert(accountID)

        // Selecting a deleted account would leave the UI pointing at nothing.
        // A deletion the app can point at is one of the few things allowed to
        // correct the context.
        if storedContext.context == .account(accountID) {
            correctContextAfterDeletion()
        }
    }

    /// Repairs a context left pointing at an account that is gone.
    ///
    /// Deliberately not a new choice: it keeps the timestamp of the selection
    /// it replaces and is never published. Stamping it "now" would let an
    /// automatic fallback outrank a deliberate choice another device made
    /// between the deletion and this device hearing about it — and publishing
    /// it would push that fallback over their choice. Every device that sees
    /// the deletion performs the same repair, so they converge without anyone
    /// writing anything.
    private func correctContextAfterDeletion() {
        storedContext = StoredDataContext(context: .local, changedAt: storedContext.changedAt)
        // Including any upload the deleted choice had queued: sending it now
        // would publish this fallback under that choice's timestamp, which is
        // exactly what not stamping it "now" is meant to prevent.
        pendingContextUpload = false
        NotificationCenter.default.post(name: .dataContextDidChange, object: nil)
    }

    /// Marks a deletion as confirmed by the server. Until then it stays in the
    /// outbox and is retried, because a tombstone that never lands lets a stale
    /// device resurrect the account.
    func confirmDeletion(_ accountID: UUID) {
        pendingDeletions.remove(accountID)
        save()
    }

    /// Marks an account upload as confirmed by the server.
    ///
    /// `updatedAt` is the timestamp of the record that was actually sent: an
    /// edit made between the record being built and the server acknowledging it
    /// leaves the account dirty, or that edit would never be uploaded.
    func confirmUpload(_ accountID: UUID, updatedAt: Date? = nil) {
        if let updatedAt, let account = account(id: accountID), account.updatedAt > updatedAt {
            return
        }
        pendingUploads.remove(accountID)
        save()
    }

    func confirmMarkerUpload(instanceID: UUID) {
        pendingMarkerUploads.remove(instanceID)
        save()
    }

    /// Marks the context upload as confirmed, unless the user has chosen a
    /// different context since the uploaded record was built.
    func confirmContextUpload(changedAt: Date) {
        guard storedContext.changedAt <= changedAt else { return }
        pendingContextUpload = false
        save()
    }

    func isDeleted(_ accountID: UUID) -> Bool {
        deletedAccountIDs.contains(accountID)
    }

    /// Marks every account record dirty again.
    ///
    /// For a server that holds nothing — sync being enabled for the first time,
    /// or the zone having been deleted from another device. The outbox
    /// otherwise tracks only what changed, which says nothing about records the
    /// server never received. Tombstones are included: without them a device
    /// that still has a deleted account could put it back.
    func markAllRecordsForUpload() {
        pendingUploads.formUnion(accounts.map(\.id))
        pendingMarkerUploads.formUnion(migratedInstanceIDs)
        pendingDeletions.formUnion(deletedAccountIDs)
        pendingContextUpload = hasStoredContext
        save()
    }

    // MARK: - Upload ordering

    /// Whether an instance's marker may be published yet.
    ///
    /// Held while any account on that instance is still waiting to upload — see
    /// `pendingMarkerUploads`.
    func canUploadMarker(instanceID: UUID) -> Bool {
        !accounts(forInstance: instanceID).contains { pendingUploads.contains($0.id) }
    }

    /// Whether the selected context may be published yet.
    ///
    /// A context naming an account the server has never seen would let a fresh
    /// device fetch the selection, find no such account, and treat a merely
    /// pending account as removed.
    var canUploadContext: Bool {
        guard case let .account(id) = storedContext.context else { return true }
        return !pendingUploads.contains(id)
    }

    // MARK: - Applying synced state

    /// Applies an account fetched from another device.
    ///
    /// - Returns: `true` when the local copy is the newer one and has to be
    ///   pushed back, since the server still holds the older version.
    @discardableResult
    func applySyncedAccount(_ incoming: Account) -> Bool {
        // A tombstone dominates the account everywhere. The caller repairs the
        // server copy; here it simply never becomes local state again.
        guard !deletedAccountIDs.contains(incoming.id) else { return false }

        if let index = accounts.firstIndex(where: { $0.id == incoming.id }) {
            let existing = accounts[index]
            guard existing.isOutranked(by: incoming) else {
                guard incoming.isOutranked(by: existing) else { return false }
                // The server holds the older copy. Marked dirty rather than
                // merely re-registered with the engine, so the correction
                // survives a crash before it is sent.
                pendingUploads.insert(existing.id)
                save()
                return true
            }
            accounts[index] = incoming
        } else {
            accounts.append(incoming)
        }

        save()
        NotificationCenter.default.post(name: .accountsDidChange, object: nil)
        return false
    }

    /// Applies a deletion tombstone fetched from another device.
    ///
    /// The tombstone's presence on the server also settles our own outbox: an
    /// entry still queued here would only re-save a record that already exists.
    @discardableResult
    func applyRemoteTombstone(_ accountID: UUID) -> Account? {
        let removed = account(id: accountID)
        forgetAccount(accountID)
        pendingDeletions.remove(accountID)
        save()

        NotificationCenter.default.post(name: .accountsDidChange, object: nil)
        return removed
    }

    /// Applies a deletion *event* — the account record itself disappeared.
    ///
    /// Authorises removal just like a tombstone, but leaves the tombstone
    /// queued: a bare record deletion is not durable, and the account would come
    /// back the moment a device that never fetched this event flushes a queued
    /// edit.
    @discardableResult
    func applyRemoteAccountDeletionEvent(_ accountID: UUID) -> Account? {
        let removed = account(id: accountID)
        pendingDeletions.insert(accountID)
        forgetAccount(accountID)
        save()

        NotificationCenter.default.post(name: .accountsDidChange, object: nil)
        return removed
    }

    /// Applies a legacy-migration marker fetched from another device.
    ///
    /// The marker only ever *prevents* synthesis. It never retracts an account
    /// already synthesized here — an account record may simply be in a later
    /// fetch event, or beyond the incremental window.
    func applySyncedMigrationMarker(instanceID: UUID) {
        let isNew = !migratedInstanceIDs.contains(instanceID)
        migratedInstanceIDs.insert(instanceID)
        // Already on the server, so ours is redundant.
        pendingMarkerUploads.remove(instanceID)
        save()

        if isNew {
            NotificationCenter.default.post(name: .accountsDidChange, object: nil)
        }
    }

    // MARK: - Context

    /// Resolves a legacy instance-keyed selection onto a real account context.
    ///
    /// `DataContext(legacy:)` maps an instance UUID straight onto an account
    /// UUID, which only holds for *migrated* accounts — those deliberately
    /// reuse the instance UUID. A login created after the revamp has a random
    /// ID, so the legacy mapping would name an account that does not exist.
    func context(forLegacyInstanceID instanceID: UUID?) -> DataContext {
        guard let instanceID else { return .local }

        let candidates = accounts(forInstance: instanceID)
        guard !candidates.isEmpty else { return .local }

        // Prefer a signed-in account when the instance holds several.
        let chosen = candidates.first { status(for: $0.id) == .signedIn } ?? candidates[0]
        return .account(chosen.id)
    }

    /// Records an explicit user choice of context.
    func setContext(_ context: DataContext) {
        storedContext = StoredDataContext(context: context)
        hasStoredContext = true
        pendingContextUpload = true
        save()
        NotificationCenter.default.post(name: .dataContextDidChange, object: nil)
    }

    /// Applies a context that arrived from another device, honouring the
    /// app-managed timestamp: an older value never overwrites a newer one, so a
    /// migration write can't undo a deliberate choice made elsewhere.
    ///
    /// - Returns: `true` when the local choice is the newer one and has to be
    ///   pushed back over the stale server copy.
    @discardableResult
    func applySyncedContext(_ incoming: StoredDataContext) -> Bool {
        var incoming = incoming

        // A tombstone dominates the account everywhere, contexts included. An
        // offline device can select an account another device has deleted and
        // publish that choice with a newer timestamp; adopting it would leave
        // every device pointing at an account that is never coming back. The
        // choice's own timestamp is kept, so a later real selection still wins,
        // and every device that holds the tombstone repairs it identically.
        if let accountID = incoming.context.accountID, deletedAccountIDs.contains(accountID) {
            incoming = StoredDataContext(context: .local, changedAt: incoming.changedAt)

            LoggingService.shared.info(
                "Ignoring a synced context that names a deleted account",
                category: .general,
                details: "accountID=\(accountID)"
            )
        }

        // Before the user has ever chosen here there is nothing to order
        // against: the local value is a default stamped when this manager was
        // constructed, so a synced choice made yesterday would lose to it and a
        // fresh device would never adopt the selection at all.
        guard hasStoredContext else {
            storedContext = incoming
            hasStoredContext = true
            save()
            NotificationCenter.default.post(name: .dataContextDidChange, object: nil)
            return false
        }

        guard storedContext.isOutranked(by: incoming) else {
            guard incoming.isOutranked(by: storedContext) else { return false }
            pendingContextUpload = true
            save()
            return true
        }
        storedContext = incoming
        hasStoredContext = true
        save()
        NotificationCenter.default.post(name: .dataContextDidChange, object: nil)
        return false
    }

    // MARK: - Status

    /// Records what the app currently knows about an account's usability.
    ///
    /// Announced separately from the account *list* changing. Recomputing
    /// statuses from the Keychain is one of the things that listens for a list
    /// change, and it cannot tell that a server rejected a credential or failed
    /// to answer — so sharing one notification meant every status the API layer
    /// recorded was overwritten by the reaction to recording it.
    func setStatus(_ status: AccountStatus, for accountID: UUID) {
        guard accountStatuses[accountID] != status else { return }
        accountStatuses[accountID] = status
        NotificationCenter.default.post(name: .accountStatusesDidChange, object: nil)
    }

    /// An account with no recorded status is *unknown*, not signed out. While
    /// the identity scope is unresolved nothing can read the Keychain under the
    /// right scope, and reporting a missing credential then would tell a user
    /// with a perfectly good login to sign in again — and drop reads to local
    /// data — for as long as iCloud stayed unreachable.
    func status(for accountID: UUID) -> AccountStatus {
        if let status = accountStatuses[accountID] { return status }
        return identityScope.isResolved ? .credentialMissing : .checking
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

            // A synthesized account reuses the instance's UUID, so a tombstone
            // for that UUID is this instance's migration already having been
            // undone. It can arrive before the marker record does — both are
            // permanent, but they are separate records — so the tombstone has
            // to gate synthesis in its own right.
            guard !deletedAccountIDs.contains(instance.id) else {
                markMigrated(instance.id)
                didChange = true
                continue
            }

            // Any account on this instance means its login is already
            // represented — whether by an earlier migration or by a fresh
            // sign-in. Synthesizing beside it would leave a credential-less
            // duplicate.
            guard accounts(forInstance: instance.id).isEmpty else {
                markMigrated(instance.id)
                didChange = true
                continue
            }

            markMigrated(instance.id)
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
        // Published like any other context, but stamped at the epoch: if a real
        // choice exists anywhere it outranks this one whichever arrives first.
        pendingContextUpload = true
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

        if let ids = defaults.array(forKey: key("pendingMarkerUploads")) as? [String] {
            pendingMarkerUploads = Set(ids.compactMap(UUID.init(uuidString:)))
        }

        if let ids = defaults.array(forKey: key("deletedAccounts")) as? [String] {
            deletedAccountIDs = Set(ids.compactMap(UUID.init(uuidString:)))
        }

        pendingContextUpload = defaults.bool(forKey: key("pendingContextUpload"))
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
        defaults.set(pendingMarkerUploads.map(\.uuidString), forKey: key("pendingMarkerUploads"))
        defaults.set(deletedAccountIDs.map(\.uuidString), forKey: key("deletedAccounts"))
        defaults.set(pendingContextUpload, forKey: key("pendingContextUpload"))
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
        pendingMarkerUploads = []
        deletedAccountIDs = []
        pendingContextUpload = false

        load()
        reconcileLegacyAccounts()

        NotificationCenter.default.post(name: .accountsDidChange, object: nil)
        // The context belongs to the namespace too, so this reload replaced it.
        // Anything keyed to the selection — the legacy setting, the feed cache —
        // would otherwise keep serving the previous Apple account's data.
        NotificationCenter.default.post(name: .dataContextDidChange, object: nil)
    }
}

extension Notification.Name {
    static let accountsDidChange = Notification.Name("stream.yattee.accountsDidChange")
    /// An account's usability changed — not the list of accounts.
    static let accountStatusesDidChange = Notification.Name("stream.yattee.accountStatusesDidChange")
    static let dataContextDidChange = Notification.Name("stream.yattee.dataContextDidChange")
}
