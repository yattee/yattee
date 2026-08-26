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

        identityObserver = NotificationCenter.default.addObserver(
            forName: .credentialIdentityScopeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.identityDidChange() }
        }

        // Local edits mark themselves dirty in AccountsManager; these turn that
        // into engine registrations without every call site knowing about sync.
        accountsObserver = NotificationCenter.default.addObserver(
            forName: .accountsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.enqueueDirtyRecords() }
        }

        contextObserver = NotificationCenter.default.addObserver(
            forName: .dataContextDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.enqueueDirtyRecords() }
        }
    }

    deinit {
        for observer in [identityObserver, accountsObserver, contextObserver] {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }

    /// Handles the identity moving under a running app.
    ///
    /// Nothing is migrated between namespaces here: the previous identity's
    /// staging, outbox and bootstrap flag stay where they are, unread, and the
    /// new identity starts from its own.
    ///
    /// Internal so tests can drive it directly rather than racing a real scope
    /// resolution.
    func identityDidChange() {
        identityGeneration += 1

        guard namespace != nil else { return }
        Task { await activate() }
    }

    // MARK: - Engine attachment

    /// Connects the coordinator to a live sync engine.
    func attach(database: CKDatabase?, enqueueChanges: @escaping EnqueueChanges) {
        self.database = database
        self.enqueueChanges = enqueueChanges
    }

    /// Disconnects when the engine is torn down. The durable state — staging,
    /// outbox, bootstrap flag — is deliberately left untouched.
    func detach() {
        enqueueChanges = nil
        database = nil
    }

    // MARK: - Fetching

    /// Stages the account-category part of one fetch event.
    ///
    /// Called before the delegate returns, so the staged state is never behind
    /// the engine's change token.
    func stageFetched(records: [CKRecord], deletions: [CKRecord.ID]) {
        let accountRecords = records.filter { RecordType.accountCategory.contains($0.recordType) }
        let accountDeletions = deletions.filter { AccountRecordName.isAccountCategory($0.recordName) }

        guard !accountRecords.isEmpty || !accountDeletions.isEmpty else { return }

        guard let namespace else {
            // Staging under a guessed identity is the one thing worse than
            // losing the records: they would be applied to, and uploaded from,
            // an account they never belonged to.
            store.hasPendingIdentityRecovery = true
            LoggingService.shared.logCloudKit(
                "Dropping \(accountRecords.count + accountDeletions.count) account records fetched before the identity resolved"
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

        // Tombstone-first. A deletion that arrived in a later event than the
        // account record it kills must still be applied before it, or the
        // account becomes visible — and selectable — in between.
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
    func uploadEverything() {
        accountsManager.markAllRecordsForUpload()
        enqueueDirtyRecords()
    }

    /// Builds the record for a pending save at send time.
    ///
    /// Returning `nil` withdraws the change from the engine — used both for
    /// records that no longer exist and for records that are being *held* by the
    /// upload ordering. Holding is safe because the outbox is durable: the
    /// change is registered again as soon as what it waits on is confirmed.
    func recordToSave(named recordName: String) -> CKRecord? {
        guard let namespace, isCategoryEnabled(), store.isBootstrapCompleted(in: namespace) else { return nil }

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
            guard accountsManager.canUploadContext else { return nil }
            return mapper.toCKRecord(dataContext: accountsManager.storedContext)

        case nil:
            return nil
        }
    }

    /// Clears outbox entries the server has confirmed, and releases whatever was
    /// waiting on them.
    func didSave(records: [CKRecord]) {
        var didConfirmAccount = false

        for record in records {
            switch AccountRecordName.parse(record.recordID.recordName) {
            case let .account(id):
                accountsManager.confirmUpload(id, updatedAt: record["updatedAt"] as? Date)
                didConfirmAccount = true

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

            case nil:
                break
            }
        }

        // A marker or a context held behind one of these accounts can go now.
        if didConfirmAccount {
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
    ///
    /// The local apply matters here in a way it does not for the other
    /// categories: CloudKit never delivers back a record this device saved, so
    /// a conflict the server won would otherwise leave stale state on screen
    /// until some unrelated future change to the same record.
    func resolveConflict(local: CKRecord, server: CKRecord) async -> CKRecord {
        let resolved: CKRecord

        switch server.recordType {
        case RecordType.account:
            resolved = await conflictResolver.resolveAccountConflict(local: local, server: server)
            if let account = try? mapper.toAccount(from: resolved), !accountsManager.isDeleted(account.id) {
                accountsManager.applySyncedAccount(account)
            }

        case RecordType.dataContext:
            resolved = await conflictResolver.resolveDataContextConflict(local: local, server: server)
            if let context = try? mapper.toStoredDataContext(from: resolved) {
                accountsManager.applySyncedContext(context)
            }

        case RecordType.legacyAccountMigration, RecordType.accountDeletion:
            resolved = await conflictResolver.resolveWriteOnceConflict(local: local, server: server)

        default:
            resolved = server
        }

        return resolved
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
