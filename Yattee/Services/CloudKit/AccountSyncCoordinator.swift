//
//  AccountSyncCoordinator.swift
//  Yattee
//
//  Syncs accounts, migration markers, deletion tombstones and the selected data
//  context through the existing CKSyncEngine.
//

import CloudKit
import Foundation

/// Drives the account category of CloudKit sync.
///
/// Accounts are not SwiftData models, so they do not fit the engine's
/// model-mapping path; and they carry rules the other categories do not:
///
/// - **Absence proves nothing.** A fetch resumes from a change token and never
///   enumerates the zone, so "no account record arrived" can never mean the
///   account was deleted. Deletions are therefore permanent `AccountDeletion`
///   records, and they dominate the account everywhere they are seen.
/// - **Staging is durable and applied as a set**, tombstones first, only once
///   the zone fetch has actually succeeded — see ``AccountSyncStore``.
/// - **Nothing activates for an identity that has not bootstrapped.** A device
///   left on the previous release consumed these record types as unknown and
///   advanced its token past them, so the first launch that understands them
///   fetches the zone once from a nil token, outside the engine's own token.
/// - **Uploads are ordered.** A marker never outruns the account it describes,
///   and a context naming an account is never published before that account is.
@MainActor
final class AccountSyncCoordinator {
    typealias EnqueueChanges = @MainActor ([CKSyncEngine.PendingRecordZoneChange]) -> Void

    // MARK: - Dependencies

    private let accountsManager: AccountsManager

    /// The identity every persisted artifact is keyed by, or `nil` while it is
    /// still being resolved.
    private let namespaceProvider: @MainActor () -> String?

    private let store: AccountSyncStore
    private let mapper: CloudKitRecordMapper
    private let conflictResolver: CloudKitConflictResolver
    private let zone: CKRecordZone

    /// Whether the accounts category may activate and upload. Accounts ride the
    /// instances category (`syncInstances`) under the iCloud master toggle.
    private let isCategoryEnabled: @MainActor () -> Bool

    /// Registers changes with the engine. `nil` while no engine exists — the
    /// dirty outbox in `AccountsManager` is the durable record, so nothing is
    /// lost by not having one.
    private var enqueueChanges: EnqueueChanges?

    /// Drops the conflict-resolved account records the engine holds for upload.
    /// That cache is keyed by record name only, and the names are deterministic
    /// across identities, so it is emptied when the identity moves rather than
    /// left holding the previous one's records. Their stamps would refuse them
    /// anyway; this is what keeps them from lingering in memory until they do.
    private var discardCachedRecords: (@MainActor () -> Void)?

    /// The private database, for the bootstrap fetch that runs outside the
    /// engine's change token.
    private weak var database: CKDatabase?

    /// Called when an account is deleted anywhere, so its credential and stored
    /// login identifier go with it.
    ///
    /// The account is `nil` when this device never had its metadata — a
    /// tombstone and the account it kills are separate records, and a fresh
    /// device can meet the tombstone first. The credential may still have
    /// arrived on its own through iCloud Keychain, so the ID alone has to be
    /// enough to remove it.
    var onAccountDeleted: (@MainActor (UUID, Account?) -> Void)?

    /// Called whenever the accounts in memory are readable for the current
    /// identity — the state in which this coordinator can say what they owe.
    ///
    /// Anything that had to be refused during the reload gap gets its second
    /// chance here rather than waiting for the next launch. Fired on every
    /// announcement, not only on the transition, so a listener that cares must
    /// be idempotent and cheap to refuse.
    var onAccountsBecameReadable: (@MainActor () -> Void)?

    // MARK: - Identity

    /// Bumped on every observed change of identity. Async work captures it and
    /// refuses to persist or activate results if it has moved — a fetch begun
    /// under one Apple account must never land in another's state.
    private var identityGeneration = 0

    /// The last identity that was actually resolved, which a later `nil` does
    /// not clear — it is the other candidate owner of anything fetched while
    /// no identity was resolved.
    private var lastResolvedNamespace: String?


    private var isActivating = false
    private var activationRequested = false

    /// Set while staged changes are being applied. Applying posts the very
    /// notifications this coordinator retries deferred activations from, so
    /// without it a run would ask itself to run again.
    private var isApplyingStagedChanges = false

    private nonisolated(unsafe) var identityObserver: NSObjectProtocol?
    private nonisolated(unsafe) var accountsObserver: NSObjectProtocol?
    private nonisolated(unsafe) var contextObserver: NSObjectProtocol?

    /// The identity everything is namespaced by, or `nil` while unresolved.
    private var namespace: String? { namespaceProvider() }

    // MARK: - Initialization

    convenience init(
        accountsManager: AccountsManager,
        identityScope: CredentialIdentityScope,
        store: AccountSyncStore? = nil,
        conflictResolver: CloudKitConflictResolver = CloudKitConflictResolver(),
        zone: CKRecordZone = RecordType.createZone(),
        isCategoryEnabled: @escaping @MainActor () -> Bool
    ) {
        // Accounts share the credential identity namespace: the account list
        // and the credentials it points at must always describe the same Apple
        // account. Held strongly — the scope is a shared service that knows
        // nothing about this coordinator, so there is no cycle to break, and a
        // weak reference would silently turn every namespaced operation into a
        // no-op if the scope were ever the shorter-lived of the two.
        self.init(
            accountsManager: accountsManager,
            namespaceProvider: { identityScope.current },
            identityScope: identityScope,
            store: store,
            conflictResolver: conflictResolver,
            zone: zone,
            isCategoryEnabled: isCategoryEnabled
        )
    }

    /// Designated initializer, and the seam tests use to move the identity
    /// deterministically instead of racing a real scope resolution.
    init(
        accountsManager: AccountsManager,
        namespaceProvider: @escaping @MainActor () -> String?,
        identityScope: CredentialIdentityScope? = nil,
        store: AccountSyncStore? = nil,
        conflictResolver: CloudKitConflictResolver = CloudKitConflictResolver(),
        zone: CKRecordZone = RecordType.createZone(),
        isCategoryEnabled: @escaping @MainActor () -> Bool
    ) {
        self.accountsManager = accountsManager
        self.namespaceProvider = namespaceProvider
        self.store = store ?? AccountSyncStore()
        self.conflictResolver = conflictResolver
        self.zone = zone
        self.mapper = CloudKitRecordMapper(zone: zone)
        self.isCategoryEnabled = isCategoryEnabled
        self.lastResolvedNamespace = namespaceProvider()

        // Observed on *this* scope: another one resolving says nothing about
        // the identity these records are namespaced by. Tests pass no scope and
        // drive `identityDidChange()` directly.
        if let identityScope {
            identityObserver = NotificationCenter.default.addObserver(
                forName: .credentialIdentityScopeDidChange,
                object: identityScope,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.identityDidChange() }
            }
        }

        // Local edits mark themselves dirty in AccountsManager; these turn that
        // into engine registrations without every call site knowing about sync.
        // They are also how `reloadForCurrentIdentity()` announces itself, which
        // is what releases records held back by the reload fence.
        accountsObserver = NotificationCenter.default.addObserver(
            forName: .accountsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.accountStateDidChange() }
        }

        contextObserver = NotificationCenter.default.addObserver(
            forName: .dataContextDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.accountStateDidChange() }
        }
    }

    deinit {
        for observer in [identityObserver, accountsObserver, contextObserver] {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }

    /// Handles the identity moving under a running app.
    ///
    /// Nothing is migrated between namespaces: the previous identity's staging,
    /// outbox and bootstrap flag stay where they are, unread, and the new one
    /// starts from its own. Bumping the generation is what makes that stick —
    /// work already in flight for the previous identity refuses to apply its
    /// results afterwards.
    ///
    /// Internal so tests can drive it directly rather than racing a real scope
    /// resolution.
    func identityDidChange() {
        identityGeneration += 1

        // Records already built for the previous identity are still sitting in
        // the engine's conflict cache, which is not namespaced and would serve
        // them at send time behind this coordinator's back.
        discardCachedRecords?()

        guard namespace != nil else { return }
        Task { await activate() }
    }

    /// Re-runs an activation that was held back because `AccountsManager` had
    /// not reloaded yet.
    ///
    /// Only meaningful while something is staged and unapplied — activation
    /// itself posts the notifications this is called from, so it would
    /// otherwise ask for a run on the way out of every run it performs.
    private func accountStateDidChange() {
        enqueueDirtyRecords()

        guard !isApplyingStagedChanges else { return }
        guard let namespace, isManagerLoaded(for: namespace) else { return }

        // Announced before the staging check below returns: the accounts being
        // readable is the news, and it is news whether or not anything is
        // staged.
        onAccountsBecameReadable?()

        guard !store.stagedChanges(in: namespace).isEmpty else { return }

        // Detached: this observer runs inside the sync-engine delegate's
        // callback tree when `handleFetchedChanges` applies account records and
        // posts `.accountsDidChange`, and an unstructured task would inherit
        // that scope — where a call back into the engine is a trap.
        Task.detached { [weak self] in await self?.activate() }
    }

    // MARK: - Engine attachment

    /// Connects the coordinator to a live sync engine.
    ///
    /// - Parameter discardingCachedRecords: empties whatever account records the
    ///   engine is holding from conflict resolution, for when the identity moves.
    func attach(
        database: CKDatabase?,
        discardingCachedRecords discardCachedRecords: (@MainActor () -> Void)? = nil,
        enqueueChanges: @escaping EnqueueChanges
    ) {
        self.database = database
        self.enqueueChanges = enqueueChanges
        self.discardCachedRecords = discardCachedRecords
    }

    /// Disconnects when the engine is torn down. The durable state — staging,
    /// outbox, bootstrap flag — is deliberately left untouched.
    func detach() {
        enqueueChanges = nil
        discardCachedRecords = nil
        database = nil
    }

    // MARK: - Fetching

    /// Notes which identity the fetch now starting belongs to.
    ///
    /// The engine's fetch spans several delegate events, and the Apple account
    /// can move between them. Staging under whatever is current when the
    /// records happen to arrive would file one identity's accounts under
    /// another's.
    func fetchDidBegin() {
        fetchIdentity = (namespace, identityGeneration)
    }

    private var fetchIdentity: (namespace: String?, generation: Int)?

    /// Stages the account-category part of one fetch event.
    ///
    /// Called before the delegate returns, so the staged state is never behind
    /// the engine's change token.
    func stageFetched(records: [CKRecord], deletions: [CKRecord.ID]) {
        let accountRecords = records.filter { RecordType.accountCategory.contains($0.recordType) }
        let accountDeletions = deletions.filter { AccountRecordName.isAccountCategory($0.recordName) }

        guard !accountRecords.isEmpty || !accountDeletions.isEmpty else { return }

        // The identity the *fetch* began under, not whatever is current now.
        let owner = fetchIdentity ?? (namespace, identityGeneration)

        guard let namespace = owner.namespace, owner.generation == identityGeneration else {
            // Staging under a guessed identity is the one thing worse than
            // losing the records: they would be applied to, and uploaded from,
            // an account they never belonged to. A bootstrap recovers them for
            // whichever identity they turn out to belong to.
            store.hasPendingIdentityRecovery = true
            LoggingService.shared.logCloudKit(
                "Dropping \(accountRecords.count + accountDeletions.count) account records fetched under an identity that has since moved"
            )
            return
        }

        store.stage(records: accountRecords, deletions: accountDeletions, in: namespace)

        LoggingService.shared.logCloudKit(
            "Staged \(accountRecords.count) account records, \(accountDeletions.count) deletions"
        )
    }

    /// Notes the outcome of a zone fetch and activates when it succeeded.
    ///
    /// The zone result — not `didFetchChanges` — is the gate: that event carries
    /// only the fetch context and fires after a partial or failed zone fetch
    /// just as it does after a complete one.
    func zoneFetchCompleted(zoneID: CKRecordZone.ID, error: CKError?) async {
        guard zoneID.zoneName == zone.zoneID.zoneName else { return }

        if let error {
            LoggingService.shared.logCloudKitError(
                "Account records stay staged: the zone fetch failed",
                error: error
            )
            return
        }

        await activate()
    }

    // MARK: - Activation

    /// Applies everything staged, once it is allowed to.
    ///
    /// Deliberately a no-op while the category is off: the records stay staged
    /// (the "deferred records" of a disabled category) rather than being
    /// discarded, because clearing engine state to refetch them later would
    /// throw away other categories' pending changes.
    func activate() async {
        // The bootstrap inside makes this suspend, and it is driven by several
        // independent signals — every zone fetch, an identity change, the
        // category being switched back on. Overlapping runs would fetch the
        // whole zone twice; a request arriving during one is replayed after it
        // rather than dropped, since it may be the one that can finally proceed.
        guard !isActivating else {
            activationRequested = true
            return
        }
        isActivating = true
        defer { isActivating = false }

        repeat {
            activationRequested = false
            await performActivation()
        } while activationRequested
    }

    private func performActivation() async {
        guard let namespace else { return }
        guard isCategoryEnabled() else {
            LoggingService.shared.logCloudKit("Account sync category is off — incoming records stay deferred")
            return
        }

        recoverDroppedRecordsIfNeeded(in: namespace)
        lastResolvedNamespace = namespace

        await runBootstrapIfNeeded(in: namespace)

        guard store.isBootstrapCompleted(in: namespace) else { return }
        guard namespace == self.namespace else { return }

        // Applying is a write into `AccountsManager`'s memory, and during the
        // reload gap that memory still belongs to the identity being left. The
        // damage is not hypothetical: an incoming account whose deterministic ID
        // matches a tombstone the *previous* identity holds would be read as a
        // resurrection and deleted from the new identity's zone, and a tombstone
        // applied against the previous identity's list removes that account —
        // taking its Keychain credential with it. Staging is durable, so this
        // defers rather than drops; `accountStateDidChange()` retries it when the
        // reload announces itself.
        guard isManagerLoaded(for: namespace) else {
            LoggingService.shared.logCloudKit(
                "Account records stay staged: the accounts in memory still belong to the previous identity"
            )
            return
        }

        applyStagedChanges(in: namespace)
        enqueueDirtyRecords()
    }

    /// Makes every identity that could have owned dropped records fetch its zone
    /// again.
    ///
    /// Which identity they belonged to cannot be reconstructed — a first launch
    /// and a sign-out followed by a different sign-in look identical from here —
    /// so instead of guessing, each candidate recovers its own records from its
    /// own zone. A redundant full fetch is the whole cost; guessing wrongly
    /// would show one Apple account's logins under another's.
    ///
    /// Only the identity signed in now and the last one seen in this process are
    /// candidates. An identity that owned dropped records, is not signed in now,
    /// and was last seen in an earlier process keeps its completed flag; nothing
    /// here knows it exists.
    private func recoverDroppedRecordsIfNeeded(in namespace: String) {
        guard store.hasPendingIdentityRecovery else { return }
        store.hasPendingIdentityRecovery = false

        for candidate in Set([namespace, lastResolvedNamespace].compactMap { $0 }) {
            store.clearBootstrapCompletion(in: candidate)
        }

        LoggingService.shared.logCloudKit(
            "Account records arrived before the identity resolved — bootstrapping again to recover them"
        )
    }

    private func applyStagedChanges(in namespace: String) {
        let staged = store.stagedChanges(in: namespace)
        guard !staged.isEmpty else { return }

        isApplyingStagedChanges = true
        defer { isApplyingStagedChanges = false }

        // Applied by category rather than in the order the records happened to
        // be fetched, because each category depends on the ones before it.
        //
        // Tombstone-first: a deletion that arrived in a later event than the
        // account record it kills must still be applied before it, or the
        // account becomes visible — and selectable — in between.
        //
        // Contexts last: repairing a context naming a deleted account reads the
        // accounts and the instance a dominated record left behind, and a repair
        // evaluated before that state exists lands on local past a signed-in
        // sibling on the same server, with nothing to re-run it afterwards.
        //
        // Only within a batch, which is what a fetch delivers and what a
        // deferred activation accumulates. A context applied in an *earlier*
        // batch than the account record that says where the deleted account
        // lived still repairs without it; the next explicit choice anywhere
        // settles that, and re-repairing on every later record would undo
        // choices made in between.
        let tombstones = staged.filter { change in
            switch AccountRecordName.parse(change.recordName) {
            case .accountDeletion: return change.kind == .save
            case .account: return change.kind == .delete
            default: return false
            }
        }
        let markers = staged.filter {
            if case .legacyMigration = AccountRecordName.parse($0.recordName) { return $0.kind == .save }
            return false
        }
        let accounts = staged.filter {
            if case .account = AccountRecordName.parse($0.recordName) { return $0.kind == .save }
            return false
        }
        let contexts = staged.filter {
            if case .dataContext = AccountRecordName.parse($0.recordName) { return $0.kind == .save }
            return false
        }

        for change in tombstones { applyTombstone(change) }
        for change in markers { applyMarker(change) }
        for change in accounts { applyAccount(change) }
        for change in contexts { applyContext(change) }

        // Deletions of markers and tombstones are ignored on purpose: both are
        // permanent by contract, and honouring their removal would let a device
        // resynthesize an account the user deleted.
        store.clearStagedChanges(in: namespace)

        LoggingService.shared.logCloudKit(
            "Applied account changes: \(tombstones.count) deletions, \(markers.count) markers, \(accounts.count) accounts, \(contexts.count) contexts"
        )
    }

    private func applyTombstone(_ change: StagedAccountChange) {
        switch AccountRecordName.parse(change.recordName) {
        case let .accountDeletion(accountID):
            guard let record = change.record(),
                  let id = try? mapper.toAccountDeletionID(from: record) else { return }
            let removed = accountsManager.applyRemoteTombstone(id)
            cleanUpCredentials(for: removed, accountID: accountID)

        case let .account(accountID):
            // The record itself was deleted. Authoritative, but not durable —
            // AccountsManager keeps the tombstone queued so this device
            // publishes one.
            let removed = accountsManager.applyRemoteAccountDeletionEvent(accountID)
            cleanUpCredentials(for: removed, accountID: accountID)

        default:
            break
        }
    }

    private func cleanUpCredentials(for account: Account?, accountID: UUID) {
        onAccountDeleted?(accountID, account)
        LoggingService.shared.logCloudKit("Removed deleted account from iCloud: \(accountID)")
    }

    private func applyMarker(_ change: StagedAccountChange) {
        guard let record = change.record(),
              let instanceID = try? mapper.toLegacyMigrationInstanceID(from: record) else { return }
        accountsManager.applySyncedMigrationMarker(instanceID: instanceID)
    }

    private func applyAccount(_ change: StagedAccountChange) {
        guard let record = change.record() else { return }

        let account: Account
        do {
            account = try mapper.toAccount(from: record)
        } catch {
            LoggingService.shared.logCloudKitError("Could not read an account record", error: error)
            return
        }

        // Convergent repair. CloudKit enforces no relationship between an
        // account and its tombstone, so a device that has not fetched the
        // deletion can recreate the record. Every device that holds the
        // tombstone ignores it locally and deletes it again server-side; the
        // window is bounded by fetch propagation, not by trust.
        guard !accountsManager.isDeleted(account.id) else {
            // The record is discarded, but not before it says where the account
            // lived: a device that met the tombstone first has no other source
            // for that, and a context repair without it lands on local past a
            // signed-in sibling on the same server.
            accountsManager.recordDeletedAccountInstance(account.instanceID, for: account.id)
            LoggingService.shared.logCloudKit("Ignoring resurrected account \(account.id) and re-deleting it")
            enqueueChanges?([.deleteRecord(recordID(for: .account(id: account.id)))])
            return
        }

        if accountsManager.applySyncedAccount(account) {
            // The server still holds the older version.
            enqueueChanges?([.saveRecord(recordID(for: .account(id: account.id)))])
        }
    }

    private func applyContext(_ change: StagedAccountChange) {
        guard let record = change.record(),
              let incoming = try? mapper.toStoredDataContext(from: record) else { return }

        if accountsManager.applySyncedContext(incoming) {
            enqueueChanges?([.saveRecord(recordID(for: .dataContext))])
        }
    }

    // MARK: - Bootstrap

    /// Fetches the zone once from a nil change token, applying only account
    /// records, so an upgrade picks up everything a previous version consumed
    /// as an unknown record type.
    ///
    /// Runs outside the engine's own token: the engine's state and every other
    /// category's pending changes are untouched.
    private func runBootstrapIfNeeded(in namespace: String) async {
        guard !store.isBootstrapCompleted(in: namespace) else { return }
        guard let database else { return }

        let generation = identityGeneration

        LoggingService.shared.logCloudKit("Bootstrapping account records with a full zone fetch")

        // CloudKit invokes the per-record blocks on its own queue, so the
        // results are collected behind a lock rather than in captured vars.
        let collector = BootstrapCollector()

        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        configuration.previousServerChangeToken = nil

        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zone.zoneID],
            configurationsByRecordZoneID: [zone.zoneID: configuration]
        )
        operation.fetchAllChanges = true

        operation.recordWasChangedBlock = { _, result in
            guard case let .success(record) = result else { return }
            guard RecordType.accountCategory.contains(record.recordType) else { return }
            collector.add(record: record)
        }

        operation.recordWithIDWasDeletedBlock = { recordID, _ in
            guard AccountRecordName.isAccountCategory(recordID.recordName) else { return }
            collector.add(deletion: recordID)
        }

        operation.recordZoneFetchResultBlock = { _, result in
            if case let .failure(error) = result { collector.recordZoneError(error) }
        }

        let outcome: Result<Void, Error> = await withCheckedContinuation { continuation in
            operation.fetchRecordZoneChangesResultBlock = { result in
                continuation.resume(returning: result)
            }
            database.add(operation)
        }

        let (fetched, deleted, zoneError) = collector.results()

        // Both results have to succeed. A partial bootstrap leaves the flag
        // unset and runs again, which is why nothing is staged until here.
        if case let .failure(error) = outcome {
            if Self.isMissingZone(error) || zoneError.map(Self.isMissingZone) == true {
                // Nothing has ever been written to this zone, so there is
                // nothing for a bootstrap to recover.
                guard identityGeneration == generation, namespace == self.namespace else { return }
                store.markBootstrapCompleted(in: namespace)
                return
            }
            LoggingService.shared.logCloudKitError("Account bootstrap fetch failed", error: error)
            return
        }
        if let zoneError {
            if Self.isMissingZone(zoneError) {
                guard identityGeneration == generation, namespace == self.namespace else { return }
                store.markBootstrapCompleted(in: namespace)
                return
            }
            LoggingService.shared.logCloudKitError("Account bootstrap zone fetch failed", error: zoneError)
            return
        }

        // The fetch began under one identity and may be finishing under
        // another; its results belong to the identity that asked for them.
        guard identityGeneration == generation, namespace == self.namespace else {
            LoggingService.shared.logCloudKit("Discarding an account bootstrap that finished under a different Apple account")
            return
        }

        store.stage(records: fetched, deletions: deleted, in: namespace)
        store.markBootstrapCompleted(in: namespace)

        LoggingService.shared.logCloudKit(
            "Account bootstrap staged \(fetched.count) records, \(deleted.count) deletions"
        )
    }

    // MARK: - Uploading

    /// Registers everything the outbox still owes the server.
    ///
    /// Safe to call repeatedly: the engine collapses duplicate pending changes,
    /// and each entry is cleared only by a server confirmation.
    func enqueueDirtyRecords() {
        guard let enqueueChanges, let namespace else { return }
        guard isCategoryEnabled(), store.isBootstrapCompleted(in: namespace) else { return }
        guard isManagerLoaded(for: namespace) else { return }

        var changes: [CKSyncEngine.PendingRecordZoneChange] = []

        // Tombstones first, and on their own: the account record's deletion is
        // registered when the tombstone is confirmed. A deletion whose
        // tombstone never landed is exactly how a stale device resurrects an
        // account, so the durable half goes first.
        for accountID in accountsManager.pendingDeletions {
            changes.append(.saveRecord(recordID(for: .accountDeletion(accountID: accountID))))
        }

        for accountID in accountsManager.pendingUploads {
            changes.append(.saveRecord(recordID(for: .account(id: accountID))))
        }

        for instanceID in accountsManager.pendingMarkerUploads
        where accountsManager.canUploadMarker(instanceID: instanceID) {
            changes.append(.saveRecord(recordID(for: .legacyAccountMigration(instanceID: instanceID))))
        }

        if accountsManager.pendingContextUpload, accountsManager.canUploadContext {
            changes.append(.saveRecord(recordID(for: .dataContext)))
        }

        guard !changes.isEmpty else { return }
        enqueueChanges(changes)
    }

    /// Registers every account record for upload, for a zone with nothing in it
    /// — first enable, or a zone recreated after being deleted elsewhere.
    ///
    /// - Returns: whether the outbox was re-primed. `false` means this device
    ///   cannot say what its accounts owe right now — the identity is simulated,
    ///   unresolved, or the accounts in memory still belong to the previous one
    ///   — and the caller has to come back to it rather than treat the re-seed
    ///   as done.
    @discardableResult
    func uploadEverything() -> Bool {
        // Marking everything dirty commits the *in-memory* list to this
        // identity's zone, so it must not run against a snapshot loaded under
        // another one.
        guard let namespace, isManagerLoaded(for: namespace) else { return false }

        accountsManager.markAllRecordsForUpload()
        enqueueDirtyRecords()
        return true
    }

    /// Drops what this device still owed the zone, and what it had cached from
    /// it.
    ///
    /// For a zone the account owner purged: CloudKit requires that data deleted
    /// that way is not sent back, and the outbox is exactly a list of records
    /// to send. The accounts themselves stay — they are this device's own, and
    /// the purge was about the copy in iCloud — so what is lost is the intent to
    /// upload them, which the next edit or the next full seed re-creates.
    ///
    /// - Returns: whether the outbox was actually emptied, on the same terms as
    ///   `uploadEverything()` — a caller that has to record the purge as handled
    ///   must come back to it otherwise.
    @discardableResult
    func discardWhatTheZoneHeld() -> Bool {
        guard let namespace else { return false }

        // Fenced before anything is destroyed, the way `uploadEverything()` is:
        // during the reload gap the accounts in memory are still the previous
        // identity's, and dropping their staging and their outbox here would
        // answer this purge with someone else's data. The purge is answered
        // again when they arrive.
        guard isManagerLoaded(for: namespace) else { return false }

        store.clearStagedChanges(in: namespace)
        accountsManager.clearPendingUploads()
        return true
    }

    /// Whether the account manager's in-memory state belongs to the namespace
    /// this coordinator uploads into.
    ///
    /// The identity scope moves before `AccountsManager` reloads — the reload
    /// runs from a main-queue observer — so in that window `namespace` already
    /// names the new identity while the accounts, the outboxes and the selected
    /// context in memory are still the previous one's. Engine callbacks can
    /// land there, and building records from that snapshot would publish one
    /// Apple account's accounts into another's zone. Observer ordering is not
    /// contractual, so this fences rather than assuming an order; the outbox is
    /// durable, and the reload re-enqueues whatever is still owed.
    private func isManagerLoaded(for namespace: String) -> Bool {
        accountsManager.loadedNamespace == namespace
    }

    /// Whether an account-category record belongs to the identity that is
    /// current now — and may therefore be uploaded, cached for retry, or have
    /// its confirmation acted on.
    ///
    /// Judged on the record's own stamp rather than on anything kept beside it.
    /// A side table keyed by record name cannot answer this: the names are
    /// deterministic, so two identities' copies of the "same" record collide in
    /// it, and the second send silently relabels the first one's. The engine
    /// also delivers delegate events from a previous identity to the same
    /// instance, and an async conflict handler can resume long after the
    /// identity moved — both arrive holding a record, which is the one thing
    /// that still knows where it came from.
    ///
    /// An unstamped record fails closed: nothing this build sends is unstamped,
    /// so it is not ours to act on.
    func belongsToCurrentIdentity(_ record: CKRecord) -> Bool {
        guard let namespace, isManagerLoaded(for: namespace) else { return false }
        return record[AccountRecordName.identityNamespaceField] as? String == namespace
    }

    /// Builds the record for a pending save at send time.
    ///
    /// Returning `nil` withdraws the change from the engine — used both for
    /// records that no longer exist and for records that are being *held* by the
    /// upload ordering. Holding is safe because the outbox is durable: the
    /// change is registered again as soon as what it waits on is confirmed.
    func recordToSave(named recordName: String) -> CKRecord? {
        guard let namespace, isCategoryEnabled(), store.isBootstrapCompleted(in: namespace) else { return nil }
        guard isManagerLoaded(for: namespace) else { return nil }

        // Stamped at the moment of building, which is the only moment that says
        // for certain whose zone this copy of the record is going into. It
        // travels with the record from here on: to the server, back in the
        // confirmation, and into the engine's retry cache.
        let record = buildRecord(named: recordName)
        record?[AccountRecordName.identityNamespaceField] = namespace as CKRecordValue

        return record
    }

    private func buildRecord(named recordName: String) -> CKRecord? {
        switch AccountRecordName.parse(recordName) {
        case let .account(id):
            guard !accountsManager.isDeleted(id), let account = accountsManager.account(id: id) else { return nil }
            return mapper.toCKRecord(account: account)

        case let .legacyMigration(instanceID):
            guard accountsManager.migratedInstanceIDs.contains(instanceID),
                  accountsManager.canUploadMarker(instanceID: instanceID) else { return nil }
            return mapper.toCKRecord(legacyMigrationInstanceID: instanceID)

        case let .accountDeletion(accountID):
            guard accountsManager.isDeleted(accountID) else { return nil }
            return mapper.toCKRecord(accountDeletionID: accountID)

        case .dataContext:
            // The pending flag, not just the ordering: correcting away from a
            // deleted account clears it deliberately, and sending that
            // automatic fallback would publish it under the deleted choice's
            // timestamp — over a deliberate choice made elsewhere.
            guard accountsManager.pendingContextUpload, accountsManager.canUploadContext else { return nil }
            return mapper.toCKRecord(dataContext: accountsManager.storedContext)

        case nil:
            return nil
        }
    }

    /// Clears outbox entries the server has confirmed, and releases whatever was
    /// waiting on them.
    ///
    /// A confirmation only ever clears state for the identity that sent the
    /// record. The names are deterministic, so the identity that took over
    /// during the send has an outbox entry under the same name; honouring the
    /// previous identity's confirmation would clear that entry without the
    /// server having confirmed anything — and, for a tombstone, register the
    /// deletion of the new identity's live account record.
    func didSave(records: [CKRecord]) {
        var didSaveAccountRecord = false
        var didIgnoreConfirmation = false

        for record in records {
            let recordName = record.recordID.recordName

            guard !AccountRecordName.isAccountCategory(recordName) || belongsToCurrentIdentity(record) else {
                // Left pending rather than confirmed: the outbox is durable and
                // the record is registered again for whichever identity still
                // owes it. Nothing is enqueued from here — least of all the
                // deletion a tombstone's confirmation releases.
                didIgnoreConfirmation = true
                LoggingService.shared.logCloudKit(
                    "Ignoring a confirmation for \(recordName) sent under a different Apple account"
                )
                continue
            }

            switch AccountRecordName.parse(recordName) {
            case let .account(id):
                accountsManager.confirmUpload(id, updatedAt: record["updatedAt"] as? Date)
                didSaveAccountRecord = true

            case let .legacyMigration(instanceID):
                accountsManager.confirmMarkerUpload(instanceID: instanceID)

            case let .accountDeletion(accountID):
                accountsManager.confirmDeletion(accountID)
                // Only now is removing the account record safe to attempt: the
                // durable half of the deletion exists.
                enqueueChanges?([.deleteRecord(recordID(for: .account(id: accountID)))])

            case .dataContext:
                if let changedAt = record["changedAt"] as? Date {
                    accountsManager.confirmContextUpload(changedAt: changedAt)
                }
                didSaveAccountRecord = true

            case nil:
                break
            }
        }

        // Whatever was held behind these can go now — a marker waiting on its
        // account, or a context the user changed while the previous one was
        // still in flight, which confirmation deliberately left dirty.
        //
        // An ignored confirmation needs the same call, for the opposite reason:
        // the send it belonged to consumed the engine's pending change for that
        // record name, and the current identity's reload — which is what would
        // otherwise re-register it — has already been and gone. Without this the
        // entry stays owed in a durable outbox that nothing is reading.
        if didSaveAccountRecord || didIgnoreConfirmation {
            enqueueDirtyRecords()
        }
    }

    /// Whether the engine should retry a save that failed with `unknownItem`
    /// as a fresh insert.
    ///
    /// It must not for an account a tombstone dominates: reinserting is exactly
    /// how a queued offline edit resurrects a deleted account.
    func shouldRetryAsInsert(recordName: String) -> Bool {
        guard case let .account(id) = AccountRecordName.parse(recordName) else { return true }
        return !accountsManager.isDeleted(id)
    }

    /// Resolves a conflict on an account-category record, and applies the
    /// outcome locally.
    func resolveConflict(local: CKRecord, server: CKRecord) async -> CKRecord {
        let resolved: CKRecord

        switch server.recordType {
        case RecordType.account:
            resolved = await conflictResolver.resolveAccountConflict(local: local, server: server)

        case RecordType.dataContext:
            resolved = await conflictResolver.resolveDataContextConflict(local: local, server: server)

        case RecordType.legacyAccountMigration, RecordType.accountDeletion:
            resolved = await conflictResolver.resolveWriteOnceConflict(local: local, server: server)

        default:
            resolved = server
        }

        // The merge can take fields from the server's copy, including its stamp,
        // so provenance is restored from the local side: this record is a retry
        // of the record *this device built*, and that is whose zone it is going
        // into. Stamping it with whatever is current instead would launder a
        // resolution begun under the previous Apple account into the one that
        // took over while it was being computed.
        inheritProvenance(from: local, to: resolved)

        applyResolvedRecord(resolved)

        return resolved
    }

    /// Copies the identity stamp of the record a resolution started from onto
    /// its outcome.
    private func inheritProvenance(from local: CKRecord, to resolved: CKRecord) {
        guard resolved !== local else { return }
        resolved[AccountRecordName.identityNamespaceField] = local[AccountRecordName.identityNamespaceField]
    }

    /// Writes a resolution's outcome into memory.
    ///
    /// Matters here in a way it does not for the other categories: CloudKit
    /// never delivers back a record this device saved, so a conflict the server
    /// won would otherwise leave stale state on screen until some unrelated
    /// future change to the same record. Fenced on the record's own provenance —
    /// the resolution suspends, and the identity can move across that suspension.
    private func applyResolvedRecord(_ resolved: CKRecord) {
        guard belongsToCurrentIdentity(resolved) else { return }

        switch resolved.recordType {
        case RecordType.account:
            guard let account = try? mapper.toAccount(from: resolved) else { return }
            // Dominated by a tombstone, so nothing of it becomes local state —
            // beyond the instance it lived on, which a later context repair has
            // no other way to learn.
            guard !accountsManager.isDeleted(account.id) else {
                accountsManager.recordDeletedAccountInstance(account.instanceID, for: account.id)
                return
            }
            accountsManager.applySyncedAccount(account)

        case RecordType.dataContext:
            guard let context = try? mapper.toStoredDataContext(from: resolved) else { return }
            accountsManager.applySyncedContext(context)

        default:
            // Write-once records carry no local state to correct.
            break
        }
    }

    // MARK: - Helpers

    private func recordID(for type: SyncableRecordType) -> CKRecord.ID {
        type.recordID(in: zone)
    }

    /// Whether an error means the zone does not exist, in which case there is
    /// nothing for a bootstrap to recover and it counts as done.
    private static func isMissingZone(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }

        switch ckError.code {
        case .zoneNotFound, .userDeletedZone:
            return true
        case .partialFailure:
            let partial = ckError.partialErrorsByItemID?.values ?? [:].values
            return partial.contains { isMissingZone($0) }
        default:
            return false
        }
    }
}

/// Gathers a bootstrap fetch's results across CloudKit's callback queue.
private final class BootstrapCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [CKRecord] = []
    private var deletions: [CKRecord.ID] = []
    private var zoneError: Error?

    func add(record: CKRecord) {
        lock.withLock { records.append(record) }
    }

    func add(deletion recordID: CKRecord.ID) {
        lock.withLock { deletions.append(recordID) }
    }

    func recordZoneError(_ error: Error) {
        lock.withLock { zoneError = error }
    }

    func results() -> ([CKRecord], [CKRecord.ID], Error?) {
        lock.withLock { (records, deletions, zoneError) }
    }
}
