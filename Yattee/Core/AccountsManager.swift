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

    /// Whether `storedContext` holds an automatic repair rather than a choice.
    ///
    /// A repair keeps the timestamp of the selection it replaced, so every
    /// ordering comparison reads it as that choice — including the one that
    /// decides an older server copy has to be corrected. Without this the
    /// fallback would be pushed back over a deliberate choice another device
    /// made, which is exactly what not stamping it "now" is meant to prevent.
    /// Persisted beside the context, or a relaunch would forget and publish it
    /// on the next stale record it saw.
    private(set) var storedContextIsRepair = false

    /// Instances the user has deleted here.
    ///
    /// Deleting an instance deletes the accounts on it, but those accounts may
    /// not have arrived yet — CloudKit and the instance list travel
    /// separately. Remembered so a late arrival is deleted rather than
    /// installed as an orphan whose credential nothing can reach.
    private(set) var deletedInstanceIDs: Set<UUID> = []

    /// Accounts known to be deleted. Permanent, and the only thing that
    /// authorises removing an account that arrives from sync: a record's
    /// *absence* proves nothing, because a fetch resumes from a change token
    /// rather than enumerating the zone.
    private(set) var deletedAccountIDs: Set<UUID> = []

    /// Which instance each deleted account lived on.
    ///
    /// Kept beside the tombstones for one purpose: repairing a context that
    /// names a deleted account looks for another login on the same server, and
    /// by then the account record itself is gone. Device-local and never
    /// published, like the statuses that repair consults.
    private(set) var deletedAccountInstanceIDs: [UUID: UUID] = [:]

    var currentContext: DataContext { storedContext.context }

    // MARK: - Initialization

    init(
        identityScope: CredentialIdentityScope,
        instancesManager: InstancesManager? = nil,
        defaults: UserDefaults = .standard,
        unreachableRetryInterval: TimeInterval = 60
    ) {
        self.identityScope = identityScope
        self.instancesManager = instancesManager
        self.defaults = defaults
        self.unreachableRetryInterval = unreachableRetryInterval

        load()

        // A change of Apple Account changes which namespace this manager reads,
        // so everything held in memory belongs to the previous one.
        NotificationCenter.default.addObserver(
            forName: .credentialIdentityScopeDidChange,
            object: identityScope,
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

    /// Accounts whose instance is gone.
    ///
    /// Never deleted automatically: an instance can be missing because iCloud
    /// has not delivered it yet, and absence is not a deletion. The screen that
    /// lists these and offers to remove them is Phase 3 work; until it exists
    /// an orphan stays out of the selectable contexts and out of the way.
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
            correctContextAfterDeletion(onInstance: account.instanceID)
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
        let instanceID = account(id: accountID)?.instanceID

        accounts.removeAll { $0.id == accountID }
        accountStatuses[accountID] = nil
        pendingUploads.remove(accountID)
        deletedAccountIDs.insert(accountID)
        if let instanceID {
            deletedAccountInstanceIDs[accountID] = instanceID
        }

        // Selecting a deleted account would leave the UI pointing at nothing.
        // A deletion the app can point at is one of the few things allowed to
        // correct the context.
        if storedContext.context == .account(accountID) {
            correctContextAfterDeletion(onInstance: instanceID)
        }
    }

    /// Repairs a context left pointing at an account that is gone.
    ///
    /// Deliberately not a new choice: it keeps the timestamp of the selection
    /// it replaces and is never published. Stamping it "now" would let an
    /// automatic fallback outrank a deliberate choice another device made
    /// between the deletion and this device hearing about it — and publishing
    /// it would push that fallback over their choice.
    ///
    /// The devices no longer converge on the same *value* the way they did when
    /// this always chose local: a sibling is picked by status, and statuses are
    /// device-local, so a device that has no credential for the sibling repairs
    /// to local while another lands on the sibling. That is acceptable precisely
    /// because the repair is never uploaded — nothing overwrites anybody — and
    /// the next explicit choice re-converges everyone.
    private func correctContextAfterDeletion(onInstance instanceID: UUID?) {
        storedContext = StoredDataContext(
            context: repairTarget(onInstance: instanceID),
            changedAt: storedContext.changedAt
        )
        storedContextIsRepair = true
        // Including any upload the deleted choice had queued: sending it now
        // would publish this fallback under that choice's timestamp, which is
        // exactly what not stamping it "now" is meant to prevent.
        pendingContextUpload = false
        NotificationCenter.default.post(name: .dataContextDidChange, object: nil)
    }

    /// Repairs a context still naming an account this device knows was deleted.
    ///
    /// The deletion paths repair as they run, so this is for a selection that
    /// was left behind anyway: a tombstone recorded while the context named
    /// something else, or a launch that reads both back from disk. Repaired
    /// exactly like a deletion — same sibling preference, same timestamp, never
    /// published — because it *is* one, only noticed later.
    ///
    /// The tombstone is the whole authorisation. An account merely missing from
    /// the store has not been deleted, it has not arrived, and moving the
    /// selection on that is how a slow sync costs the user their choice.
    ///
    /// - Returns: `true` when the selection actually moved.
    @discardableResult
    func correctContextIfAccountDeleted() -> Bool {
        // The namespace moved and the reload has not refilled memory yet, so
        // the selection and the tombstones weighed against each other here both
        // belong to the previous identity. Fenced on the loaded namespace for
        // the same reason `save()` is: acting on that state repairs — and
        // announces — a choice the identity being switched to never made. The
        // reload replaces both sides, and the next activation asks again.
        guard loadedNamespace == namespace else { return false }

        guard case let .account(id) = storedContext.context else { return false }
        guard deletedAccountIDs.contains(id) else { return false }

        correctContextAfterDeletion(onInstance: deletedAccountInstanceIDs[id])
        save()
        return true
    }

    /// Where a context whose account was deleted should land.
    ///
    /// Another signed-in login on the same server is far closer to what the user
    /// was doing than their local data, and on an instance holding two logins it
    /// is usually the only other thing they meant. Only `signedIn` qualifies: a
    /// sibling this device cannot use would repair the context onto something
    /// that immediately falls back to local anyway, without the user's choice
    /// surviving anywhere.
    private func repairTarget(onInstance instanceID: UUID?) -> DataContext {
        guard let instanceID else { return .local }

        // Asked here rather than at the call sites because a repair commits:
        // once the selection no longer names the deleted account there is
        // nothing left for a later status to move. A deletion delivered by a
        // silent push arrives without any of the events that recompute statuses
        // — a credential can reach this device over iCloud Keychain while it is
        // in the background — so the sibling would be skipped as signed out
        // while its credential sat right there.
        refreshStatusesForRepair?()

        let sibling = accounts(forInstance: instanceID)
            .filter { status(for: $0.id) == .signedIn }
            .filter { capabilities(for: $0)?.isSelectableContext == true }
            // Ordered so the answer does not depend on which order the accounts
            // happened to arrive in, the same way a context tie is broken.
            .min { $0.id.uuidString < $1.id.uuidString }

        guard let sibling else { return .local }
        return .account(sibling.id)
    }

    /// Recomputes account statuses from the Keychain, just before a repair
    /// decides which sibling — if any — it may land on.
    ///
    /// A hook rather than a dependency for the same reason as
    /// `onSuspectedCredentialRejection`: reading the Keychain needs the
    /// credential stores, and this manager deliberately knows nothing about
    /// them. `nil` — tests, and the window before wiring completes — simply
    /// leaves the statuses as they are, which is what the repair did before.
    @ObservationIgnored var refreshStatusesForRepair: (@MainActor () -> Void)?

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

    /// Records that an instance was deleted here, so accounts on it that have
    /// yet to arrive are deleted on sight rather than orphaned.
    func recordInstanceDeletion(_ instanceID: UUID) {
        guard !deletedInstanceIDs.contains(instanceID) else { return }
        deletedInstanceIDs.insert(instanceID)
        save()
    }

    func isDeleted(_ accountID: UUID) -> Bool {
        deletedAccountIDs.contains(accountID)
    }

    /// Remembers which instance a deleted account lived on, learned from a
    /// record that arrived after its tombstone.
    ///
    /// A device that meets the tombstone first — a fresh install, or any fetch
    /// that stages both — has no account to read the instance off, and the
    /// account record that follows is dominated and discarded. That record is
    /// the only thing that still knows where the account lived, and without it
    /// every later repair of a context naming it falls to local past a
    /// perfectly good sibling on the same server.
    func recordDeletedAccountInstance(_ instanceID: UUID, for accountID: UUID) {
        // The namespace moved and the reload has not refilled memory yet, so
        // this would file one identity's deletion under another's.
        guard loadedNamespace == namespace else { return }
        guard deletedAccountIDs.contains(accountID) else { return }
        // The deletion this device performed itself read the instance off the
        // account it removed, which is closer to the truth than a record that
        // may have been resurrected since.
        guard deletedAccountInstanceIDs[accountID] == nil else { return }

        deletedAccountInstanceIDs[accountID] = instanceID
        save()
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
        // An empty zone is no reason to publish a fallback nobody chose: a
        // repair is never uploaded, however little the server holds. The next
        // explicit choice fills the gap, and until then every device keeps
        // repairing to whatever it can actually use.
        pendingContextUpload = hasStoredContext && !storedContextIsRepair
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
        // server copy; here it simply never becomes local state again — except
        // for the one thing worth keeping: which instance it lived on, for a
        // context repair that has no account left to read it off.
        guard !deletedAccountIDs.contains(incoming.id) else {
            recordDeletedAccountInstance(incoming.instanceID, for: incoming.id)
            return false
        }

        // Its instance was deleted here while this account was still in
        // transit. Deleting an instance deletes its accounts, so this one is
        // deleted too — arriving late does not exempt it, and installing it
        // would leave an orphan nothing can reach the credential of.
        guard !deletedInstanceIDs.contains(incoming.instanceID) else {
            pendingDeletions.insert(incoming.id)
            deletedAccountIDs.insert(incoming.id)
            save()

            LoggingService.shared.info(
                "An account arrived for an instance that was deleted here — deleting it too",
                category: .general,
                details: "accountID=\(incoming.id)"
            )
            return false
        }

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

        // The legacy selection may name exactly this account. Migration refuses
        // to adopt a context whose account is not there yet, and on a fresh
        // install the account arrives from iCloud long after the migration ran —
        // so it is retried here rather than left until the next launch. Free to
        // repeat: it never runs once a context has been chosen.
        let contextBefore = storedContext.context
        migrateLegacyContextIfNeeded()

        NotificationCenter.default.post(name: .accountsDidChange, object: nil)
        if storedContext.context != contextBefore {
            NotificationCenter.default.post(name: .dataContextDidChange, object: nil)
        }
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
        // Whatever stood here before, this is a choice — and choices publish.
        storedContextIsRepair = false
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
        var wasRepaired = false

        // A tombstone dominates the account everywhere, contexts included. An
        // offline device can select an account another device has deleted and
        // publish that choice with a newer timestamp; adopting it would leave
        // every device pointing at an account that is never coming back. The
        // choice's own timestamp is kept, so a later real selection still wins,
        // and the repair is never published — a device that repairs to something
        // else does not overwrite anybody.
        if let accountID = incoming.context.accountID, deletedAccountIDs.contains(accountID) {
            // Repaired the same way a local deletion is: onto a signed-in login
            // on the same server when there is one, local otherwise.
            incoming = StoredDataContext(
                context: repairTarget(onInstance: deletedAccountInstanceIDs[accountID]),
                changedAt: incoming.changedAt
            )
            wasRepaired = true

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
            adoptSyncedContext(incoming, wasRepaired: wasRepaired)
            return false
        }

        guard storedContext.isOutranked(by: incoming) else {
            // The local choice is the newer one and survives untouched — a
            // repair that lost the ordering never gets to clear what that
            // choice still owes the server.
            guard incoming.isOutranked(by: storedContext) else { return false }
            // Newer, but not a choice. A repair carries the replaced selection's
            // timestamp, so it outranks the server's older explicit value while
            // having nothing of its own to say; publishing it would push an
            // automatic fallback over that value. Nothing is uploaded here: the
            // server's context stands remotely, the repair stays local, and the
            // next explicit choice on any device re-converges everyone.
            guard !storedContextIsRepair else { return false }
            pendingContextUpload = true
            save()
            return true
        }
        adoptSyncedContext(incoming, wasRepaired: wasRepaired)
        return false
    }

    /// Takes on a context that arrived from another device.
    ///
    /// A repaired value is an automatic fallback rather than a choice, so any
    /// upload the replaced selection still owed is dropped along with it:
    /// sending it now would publish this fallback under that choice's
    /// timestamp, which is exactly what keeping the timestamp is meant to
    /// prevent — the same reasoning as `correctContextAfterDeletion`.
    private func adoptSyncedContext(_ incoming: StoredDataContext, wasRepaired: Bool) {
        storedContext = incoming
        hasStoredContext = true
        // A value adopted as it stands is somebody's choice and may be pushed
        // back if the server ever holds an older one; a repaired one may not.
        storedContextIsRepair = wasRepaired
        if wasRepaired {
            pendingContextUpload = false
        }
        save()
        NotificationCenter.default.post(name: .dataContextDidChange, object: nil)
    }

    // MARK: - Status

    /// Records what the app currently knows about an account's usability.
    ///
    /// Announced separately from the account *list* changing. Recomputing
    /// statuses from the Keychain is one of the things that listens for a list
    /// change, and it cannot tell that a server rejected a credential or failed
    /// to answer — so sharing one notification meant every status the API layer
    /// recorded was overwritten by the reaction to recording it.
    /// - Parameter date: when the verdict was reached. Only `unreachable` uses
    ///   it — to decide when to try again — and only tests pass anything but
    ///   the default.
    func setStatus(_ status: AccountStatus, for accountID: UUID) {
        unreachableExpiries[accountID]?.cancel()
        unreachableExpiries[accountID] = nil

        if status == .unreachable {
            scheduleUnreachableExpiry(for: accountID)
        }

        guard accountStatuses[accountID] != status else { return }
        accountStatuses[accountID] = status
        NotificationCenter.default.post(name: .accountStatusesDidChange, object: nil)
    }

    /// Pending "try this account again" timers.
    private var unreachableExpiries: [UUID: Task<Void, Never>] = [:]

    /// How long "could not be reached" stands before the app tries again.
    ///
    /// It has to expire on its own, and visibly: the state stops reads from
    /// going to the server at all, so nothing would discover that the server
    /// came back — and a timeout during an outage produces no connectivity
    /// change to react to either. Expiring by mutating the status, rather than
    /// by having the getter compare the clock, is what makes the fallback
    /// actually lift: nothing re-reads a value merely because time passed.
    /// Injectable so tests do not have to wait a real minute.
    private let unreachableRetryInterval: TimeInterval

    private func scheduleUnreachableExpiry(for accountID: UUID) {
        unreachableExpiries[accountID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.unreachableRetryInterval ?? 60))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.accountStatuses[accountID] == .unreachable else { return }
                self.unreachableExpiries[accountID] = nil
                // Back to being usable: the credential was never in question,
                // and the next request settles it either way.
                self.setStatus(.signedIn, for: accountID)
            }
        }
    }

    /// An account with no recorded status is *unknown*, not signed out. While
    /// the identity scope is unresolved nothing can read the Keychain under the
    /// right scope, and reporting a missing credential then would tell a user
    /// with a perfectly good login to sign in again — and drop reads to local
    /// data — for as long as iCloud stayed unreachable.
    func status(for accountID: UUID) -> AccountStatus {
        accountStatuses[accountID] ?? (identityScope.isResolved ? .credentialMissing : .checking)
    }

    /// Asked to confirm an auth-shaped failure before anything is concluded
    /// from it. `nil` — tests, and the window before wiring completes — means
    /// nothing is concluded at all, which is the safe direction.
    ///
    /// Held here as a hook rather than as a dependency because the confirmation
    /// needs an API client, and this manager deliberately knows nothing about
    /// the network.
    @ObservationIgnored var onSuspectedCredentialRejection: (@MainActor (Account) -> Void)?

    /// Records what a server call implies about the account that made it.
    ///
    /// Nothing here rejects a credential. A raw 401 or 403 is *suspicion*: the
    /// same statuses come back from a reverse proxy, from endpoints a valid
    /// session may not touch, and — on Invidious — from a genuinely revoked
    /// session, and the request that failed cannot tell them apart. It is
    /// handed to `onSuspectedCredentialRejection`, which asks the question again
    /// against an endpoint that exists to be authenticated; only that second
    /// answer marks the account. Until it arrives the status is left alone,
    /// rather than wrongly telling the user to sign in again.
    ///
    /// Shared by the subscription providers and the feed cache: a credential
    /// that expires during a feed-only refresh has to mark the account too, or
    /// nothing ever reports it and the fallback never engages.
    func recordServerOutcome(_ error: Error?, for account: Account) {
        guard let error else {
            setStatus(.signedIn, for: account.id)
            return
        }

        // A server that cannot be reached says nothing about the credential.
        // Recorded all the same: the account has to stop reporting itself as
        // usable, or reads never fall back and the user is shown failures
        // instead of local data.
        switch error {
        case APIError.timeout, APIError.noConnection:
            setStatus(.unreachable, for: account.id)
        case APIError.cancelled:
            return
        case APIError.unauthorized:
            suspectRejection(of: account)
        case let APIError.httpError(statusCode, _) where statusCode == 401 || statusCode == 403:
            // 403 arrives untranslated on purpose: the shared HTTP mapping
            // turns only 401 into `.unauthorized`, because unauthenticated call
            // sites read 403 as "this instance is blocked" rather than "this
            // login is". Both shapes mean the same thing here.
            suspectRejection(of: account)
        default:
            return
        }
    }

    /// Passes an auth-shaped failure on for confirmation, unless the instance
    /// itself can explain it.
    private func suspectRejection(of account: Account) {
        // An instance behind HTTP Basic Auth answers 401 at the proxy for every
        // request made to it, whichever account made it — so the status says
        // nothing about this credential, and a probe would only be answered by
        // the same proxy. An orphaned account, whose instance is unknown, is
        // skipped by the same guard: there is nothing to probe against.
        guard instance(for: account)?.usesBasicAuth == false else { return }

        onSuspectedCredentialRejection?(account)
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
        // Nothing may be synthesized into the unresolved namespace: the app
        // cannot yet tell whose accounts these are, and the marker it would
        // write there is permanent while the namespace itself is discarded.
        // Nothing is lost by waiting — resolution runs
        // `reloadForCurrentIdentity()`, which reconciles under the namespace
        // that will actually be read.
        guard identityScope.isResolved else { return }
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
        // A one-way migration is spent the moment it runs, so running it
        // against the unresolved namespace would consume it against storage
        // that is thrown away — and mark a context chosen that the identity
        // owning the choice never sees.
        guard identityScope.isResolved else { return }
        guard !hasStoredContext else { return }

        guard let legacy = legacySubscriptionAccount() else { return }

        let context = DataContext(legacy: legacy)

        // Only adopt a context whose account actually exists; otherwise the app
        // would start up pointing at something it cannot resolve.
        if case let .account(id) = context, account(id: id) == nil { return }

        storedContext = .migrated(context)
        hasStoredContext = true
        storedContextIsRepair = false
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

    /// Whether the identity everything here is keyed by is known.
    ///
    /// Exposed because the corrections other services make — rewriting the
    /// legacy selection, resetting a context whose account is "missing" — are
    /// only meaningful once this is true. While it is false the app is looking
    /// at a namespace it will discard, and acting on what it finds there
    /// corrects real state from state that was never authoritative.
    var isIdentityResolved: Bool { identityScope.isResolved }

    /// The namespace the in-memory state was loaded from.
    ///
    /// `namespace` moves the instant the identity scope does, but the reload
    /// that refills memory runs on a main-queue observer afterwards. In that
    /// window everything held here still belongs to the previous identity, so
    /// writes are fenced on this rather than on `namespace` — otherwise one
    /// Apple account's accounts would be persisted, and uploaded, under
    /// another's. Kept out of observation: it is a storage fence, not state
    /// anything renders.
    @ObservationIgnored private(set) var loadedNamespace = ""

    private func key(_ name: String) -> String {
        "accounts.\(namespace).\(name)"
    }

    private var hasStoredContext: Bool {
        get { defaults.bool(forKey: key("hasContext")) }
        set {
            guard loadedNamespace == namespace else { return }
            defaults.set(newValue, forKey: key("hasContext"))
        }
    }

    private func load() {
        loadedNamespace = namespace

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

        if let ids = defaults.array(forKey: key("deletedInstances")) as? [String] {
            deletedInstanceIDs = Set(ids.compactMap(UUID.init(uuidString:)))
        }

        if let pairs = defaults.dictionary(forKey: key("deletedAccountInstances")) as? [String: String] {
            deletedAccountInstanceIDs = pairs.reduce(into: [:]) { result, pair in
                guard let accountID = UUID(uuidString: pair.key),
                      let instanceID = UUID(uuidString: pair.value) else { return }
                result[accountID] = instanceID
            }
        }

        pendingContextUpload = defaults.bool(forKey: key("pendingContextUpload"))
        storedContextIsRepair = defaults.bool(forKey: key("contextIsRepair"))

        purgeUnresolvedNamespace()
    }

    /// Every key `save()` writes, for purging a namespace wholesale.
    private static let storedKeyNames = [
        "accounts", "context", "hasContext", "migrated", "pendingUploads",
        "pendingDeletions", "pendingMarkerUploads", "deletedAccounts",
        "deletedInstances", "deletedAccountInstances", "pendingContextUpload",
        "contextIsRepair"
    ]

    /// Deletes whatever was written while the identity was still unresolved.
    ///
    /// That namespace is a holding pen no resolved identity ever reads back,
    /// and what accumulates there is actively wrong: a snapshot from before a
    /// tombstone was applied, outboxes owing uploads to a zone nothing will
    /// ever send them to. With iCloud Drive switched off the scope dips to
    /// unresolved on every foreground activation, so it is written in ordinary
    /// use rather than only in exotic states.
    ///
    /// Run from `load()`, which covers both a launch that resolves immediately
    /// (where no reload ever runs) and one that resolves later. Repeatable, so
    /// there is nothing to remember about having done it.
    private func purgeUnresolvedNamespace() {
        guard identityScope.isResolved else { return }

        for name in Self.storedKeyNames {
            defaults.removeObject(forKey: "accounts.unresolved.\(name)")
        }
    }

    private func save() {
        // The namespace moved and the reload has not run yet, so this is the
        // previous identity's state being written under the new identity's
        // keys. Dropped rather than deferred: the reload that follows loads
        // whatever storage already holds for the new identity, and everything
        // dropped here is either that identity's — and still on disk — or the
        // previous one's, which its own namespace still holds.
        guard loadedNamespace == namespace else {
            LoggingService.shared.warning(
                "Dropping an account save made while the identity namespace was reloading",
                category: .general,
                details: "loaded=\(loadedNamespace), current=\(namespace)"
            )
            return
        }

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
        defaults.set(deletedInstanceIDs.map(\.uuidString), forKey: key("deletedInstances"))
        defaults.set(
            deletedAccountInstanceIDs.reduce(into: [String: String]()) { result, pair in
                result[pair.key.uuidString] = pair.value.uuidString
            },
            forKey: key("deletedAccountInstances")
        )
        defaults.set(pendingContextUpload, forKey: key("pendingContextUpload"))
        defaults.set(storedContextIsRepair, forKey: key("contextIsRepair"))
    }

    /// Re-reads storage under the current identity namespace.
    ///
    /// Called when the credential scope resolves or changes: the accounts held
    /// in memory belong to whichever namespace was active when they were loaded.
    func reloadForCurrentIdentity() {
        accounts = []
        accountStatuses = [:]
        // Their accounts belong to the namespace being left. A migrated account
        // reuses its instance's UUID, so the same ID can exist under the new
        // identity — and an old timer would then declare *that* account
        // reachable again on the strength of a verdict about someone else's.
        for expiry in unreachableExpiries.values { expiry.cancel() }
        unreachableExpiries = [:]
        storedContext = StoredDataContext(context: .local)
        migratedInstanceIDs = []
        pendingUploads = []
        pendingDeletions = []
        pendingMarkerUploads = []
        deletedAccountIDs = []
        deletedInstanceIDs = []
        deletedAccountInstanceIDs = [:]
        pendingContextUpload = false
        storedContextIsRepair = false

        load()
        reconcileLegacyAccounts()
        // Both migrations are held back while the scope is unresolved, and this
        // is where a launch that resolved late gets them. Reconciliation only
        // runs the context migration when it changed something, so a namespace
        // whose accounts were already migrated would otherwise keep its legacy
        // selection until the next relaunch. Idempotent via `hasStoredContext`.
        migrateLegacyContextIfNeeded()

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
    /// An account's stored credential was replaced. The account itself is
    /// unchanged, so anything holding data fetched with the old one has to be
    /// told: it may belong to an entirely different person on that server.
    static let accountCredentialDidChange = Notification.Name("stream.yattee.accountCredentialDidChange")
    static let dataContextDidChange = Notification.Name("stream.yattee.dataContextDidChange")
}
