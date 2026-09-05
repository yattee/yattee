//
//  AccountsManagerTests.swift
//  YatteeTests
//
//  Account storage, legacy migration and data-context validation.
//

import Testing
import Foundation
@testable import Yattee

@Suite("AccountsManager")
@MainActor
struct AccountsManagerTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "yattee.tests.\(UUID().uuidString)")!
    }

    private func makeManager(
        defaults: UserDefaults? = nil,
        scope: String = "identity-A",
        instances: InstancesManager? = nil
    ) -> AccountsManager {
        AccountsManager(
            identityScope: CredentialIdentityScope(fixedScope: scope),
            instancesManager: instances,
            defaults: defaults ?? makeDefaults()
        )
    }

    @Test("Accounts survive a relaunch")
    func accountsPersist() {
        let defaults = makeDefaults()
        let instanceID = UUID()

        let first = makeManager(defaults: defaults)
        let account = first.addAccount(instanceID: instanceID, displayName: "Main")

        let second = makeManager(defaults: defaults)
        #expect(second.account(id: account.id)?.displayName == "Main")
    }

    @Test("Accounts are namespaced by Apple account")
    func accountsAreNamespacedByIdentity() {
        let defaults = makeDefaults()
        let instanceID = UUID()

        let identityA = makeManager(defaults: defaults, scope: "identity-A")
        let account = identityA.addAccount(instanceID: instanceID)

        // The same storage, a different Apple account: A's list must not show.
        let identityB = makeManager(defaults: defaults, scope: "identity-B")
        #expect(identityB.accounts.isEmpty)
        #expect(identityB.account(id: account.id) == nil)

        let identityAAgain = makeManager(defaults: defaults, scope: "identity-A")
        #expect(identityAAgain.accounts.count == 1)
    }

    @Test("Adding an account queues it for upload")
    func addQueuesUpload() {
        let manager = makeManager()
        let account = manager.addAccount(instanceID: UUID())

        #expect(manager.pendingUploads.contains(account.id))

        manager.confirmUpload(account.id)
        #expect(!manager.pendingUploads.contains(account.id))
    }

    @Test("Deleting an account queues a deletion that survives a relaunch")
    func deletionOutboxIsDurable() {
        let defaults = makeDefaults()
        let manager = makeManager(defaults: defaults)
        let account = manager.addAccount(instanceID: UUID())

        manager.removeAccount(account.id)
        #expect(manager.pendingDeletions.contains(account.id))

        // A deletion that never reached the server must be retried, or a stale
        // device can resurrect the account.
        let relaunched = makeManager(defaults: defaults)
        #expect(relaunched.pendingDeletions.contains(account.id))
        #expect(relaunched.account(id: account.id) == nil)

        relaunched.confirmDeletion(account.id)
        #expect(!relaunched.pendingDeletions.contains(account.id))
    }

    @Test("Deleting the selected account resets the context")
    func deletingSelectedAccountResetsContext() {
        let manager = makeManager()
        let account = manager.addAccount(instanceID: UUID())

        manager.setContext(.account(account.id))
        #expect(manager.currentContext == .account(account.id))

        manager.removeAccount(account.id)
        #expect(manager.currentContext == .local)
    }

    @Test("A newer synced context wins, an older one is ignored")
    func syncedContextResolvesByTimestamp() {
        let manager = makeManager()
        let accountID = UUID()

        manager.setContext(.local)
        let localChangedAt = manager.storedContext.changedAt

        // Older than the local choice — must not take effect.
        manager.applySyncedContext(
            StoredDataContext(context: .account(accountID), changedAt: localChangedAt.addingTimeInterval(-60))
        )
        #expect(manager.currentContext == .local)

        // Newer — wins.
        manager.applySyncedContext(
            StoredDataContext(context: .account(accountID), changedAt: localChangedAt.addingTimeInterval(60))
        )
        #expect(manager.currentContext == .account(accountID))
    }

    @Test("A fresh login does not also synthesize a migrated account")
    func freshLoginDoesNotDuplicate() {
        let manager = makeManager()
        let instanceID = UUID()

        // Signing in creates a random-UUID account, then flips
        // usesAccountLogin, which re-runs reconciliation immediately.
        let account = manager.addAccount(instanceID: instanceID)
        manager.reconcileLegacyAccounts()

        #expect(manager.accounts(forInstance: instanceID).count == 1)
        #expect(manager.accounts(forInstance: instanceID).first?.id == account.id)
    }

    @Test("Storing accounts does not count as choosing a context")
    func savingDoesNotMarkContextChosen() {
        let defaults = makeDefaults()
        let instanceID = UUID()

        // Legacy selection left behind by the previous release.
        let legacy = try! JSONEncoder().encode(SubscriptionAccount.invidious(instanceID))
        defaults.set(legacy, forKey: "subscriptionAccount")

        let manager = makeManager(defaults: defaults)
        // Adding an account persists state; that must not look like the user
        // having chosen a context, or the migration below is skipped and the
        // upgrade silently loses their selected server account.
        _ = manager.addAccount(instanceID: instanceID, displayName: nil)
        manager.migrateLegacyContextIfNeeded()

        #expect(manager.currentContext == .local)

        // With the migrated account present, the legacy selection is adopted.
        let manager2 = makeManager(defaults: defaults)
        #expect(manager2.currentContext == .local)
    }

    @Test("A legacy selection migrates when its account finally syncs")
    func legacyContextMigratesOnLateAccountArrival() {
        let defaults = makeDefaults()
        let instanceID = UUID()

        let legacy = try! JSONEncoder().encode(SubscriptionAccount.invidious(instanceID))
        defaults.set(legacy, forKey: "subscriptionAccount")

        let manager = makeManager(defaults: defaults)
        // On a fresh install the accounts arrive from iCloud long after launch,
        // so the migration finds nothing to point at and adopts nothing.
        manager.migrateLegacyContextIfNeeded()
        #expect(manager.currentContext == .local)

        // The account the legacy value names, arriving at last. A migrated
        // account reuses its instance's UUID, which is what the legacy mapping
        // resolves to.
        manager.applySyncedAccount(Account.migrated(from: instanceID, dateAdded: Date()))

        #expect(manager.currentContext == .account(instanceID))
    }

    @Test("A choice made while the account was in transit is never overridden")
    func lateAccountArrivalNeverOverridesAChoice() {
        let defaults = makeDefaults()
        let instanceID = UUID()

        let legacy = try! JSONEncoder().encode(SubscriptionAccount.invidious(instanceID))
        defaults.set(legacy, forKey: "subscriptionAccount")

        let manager = makeManager(defaults: defaults)
        manager.migrateLegacyContextIfNeeded()

        // The user picked something in the meantime; a guess at what they meant
        // before the upgrade never replaces what they actually chose after it.
        let chosen = manager.addAccount(instanceID: UUID())
        manager.setContext(.account(chosen.id))

        manager.applySyncedAccount(Account.migrated(from: instanceID, dateAdded: Date()))

        #expect(manager.currentContext == .account(chosen.id))
    }

    @Test("A legacy instance selection resolves to a real account")
    func legacySelectionResolvesToRealAccount() {
        let manager = makeManager()
        let instanceID = UUID()

        // No account yet on that instance: nothing to select.
        #expect(manager.context(forLegacyInstanceID: instanceID) == .local)

        // A login created after the revamp has a random ID, so the legacy
        // instance-ID-as-account-ID mapping would name something nonexistent.
        let account = manager.addAccount(instanceID: instanceID)
        #expect(account.id != instanceID)
        #expect(manager.context(forLegacyInstanceID: instanceID) == .account(account.id))

        #expect(manager.context(forLegacyInstanceID: nil) == .local)
    }

    @Test("A signed-in account is preferred when an instance holds several")
    func legacySelectionPrefersSignedIn() {
        let manager = makeManager()
        let instanceID = UUID()

        _ = manager.addAccount(instanceID: instanceID)
        let second = manager.addAccount(instanceID: instanceID)
        manager.setStatus(.signedIn, for: second.id)

        #expect(manager.context(forLegacyInstanceID: instanceID) == .account(second.id))
    }

    @Test("An account arriving after its instance was deleted is deleted too")
    func lateAccountForDeletedInstanceIsDeleted() {
        let manager = makeManager()
        let instanceID = UUID()

        manager.recordInstanceDeletion(instanceID)

        // Deleting an instance deletes the accounts on it; one still in transit
        // does not escape that by arriving late, and installing it would leave
        // an orphan whose credential nothing can reach.
        let late = Account(instanceID: instanceID)
        #expect(!manager.applySyncedAccount(late))

        #expect(manager.account(id: late.id) == nil)
        #expect(manager.isDeleted(late.id))
        #expect(manager.pendingDeletions.contains(late.id))
    }

    @Test("An unreachable server is retried rather than written off")
    func unreachableStatusExpires() async throws {
        let manager = AccountsManager(
            identityScope: CredentialIdentityScope(fixedScope: "identity-A"),
            defaults: makeDefaults(),
            unreachableRetryInterval: 0.05
        )
        let account = manager.addAccount(instanceID: UUID())

        manager.setStatus(.unreachable, for: account.id)
        #expect(manager.status(for: account.id) == .unreachable)

        // The state stops reads from going out at all, so nothing would ever
        // discover that the server came back — a timeout during an outage
        // produces no connectivity change to react to either. It has to lift
        // by mutating the status: nothing re-reads a value because time passed.
        try await Task.sleep(for: .seconds(0.5))
        #expect(manager.status(for: account.id) == .signedIn)
    }

    @Test("A sign-in that could not be stored leaves no migration marker")
    func rolledBackLoginRetractsItsMarker() {
        let manager = makeManager()
        let instanceID = UUID()

        let account = manager.addAccount(instanceID: instanceID)
        #expect(manager.migratedInstanceIDs.contains(instanceID))

        manager.rollbackAccountCreation(account.id)

        // The marker would have told every other device that this instance's
        // pre-revamp login is already represented — on the strength of an
        // account that does not exist anywhere.
        #expect(!manager.migratedInstanceIDs.contains(instanceID))
        #expect(!manager.pendingMarkerUploads.contains(instanceID))
        #expect(manager.account(id: account.id) == nil)
        // And no tombstone: nothing was ever published to retract.
        #expect(!manager.isDeleted(account.id))
        #expect(!manager.pendingDeletions.contains(account.id))
    }

    @Test("Rolling back a confirmed account is a real deletion")
    func rolledBackConfirmedAccountIsDeleted() {
        let manager = makeManager()
        let account = manager.addAccount(instanceID: UUID())
        manager.confirmUpload(account.id)

        manager.rollbackAccountCreation(account.id)

        // It exists on the server, so other devices have to be told.
        #expect(manager.isDeleted(account.id))
        #expect(manager.pendingDeletions.contains(account.id))
    }

    @Test("An unresolved identity is not a missing credential")
    func unknownStatusIsNotSignedOut() {
        let defaults = makeDefaults()
        let unresolved = AccountsManager(
            identityScope: CredentialIdentityScope(fixedScope: nil),
            defaults: defaults
        )
        let account = unresolved.addAccount(instanceID: UUID())

        // Nothing can read the Keychain under the right scope yet, so "no
        // credential" is not an answer the app is entitled to give.
        #expect(unresolved.status(for: account.id) == .checking)

        let resolved = makeManager(defaults: defaults, scope: "identity-A")
        let other = resolved.addAccount(instanceID: UUID())
        #expect(resolved.status(for: other.id) == .credentialMissing)
    }

    @Test("A fresh device adopts the synced context")
    func firstSyncedContextIsAdopted() {
        let manager = makeManager()
        let accountID = UUID()

        // The local value is a default stamped when the manager was built, so
        // it is always "newer" than a choice made on another device yesterday.
        // Ordering against it would leave a fresh device on local forever.
        let synced = StoredDataContext(
            context: .account(accountID),
            changedAt: Date().addingTimeInterval(-86_400)
        )

        #expect(!manager.applySyncedContext(synced))
        #expect(manager.currentContext == .account(accountID))
        #expect(!manager.pendingContextUpload)
    }

    @Test("Correcting away from a deleted account never outranks a real choice")
    func deletionCorrectionIsNotAChoice() {
        let manager = makeManager()
        let account = manager.addAccount(instanceID: UUID())

        manager.setContext(.account(account.id))
        let chosenAt = manager.storedContext.changedAt
        manager.confirmContextUpload(changedAt: chosenAt)

        manager.removeAccount(account.id)
        #expect(manager.currentContext == .local)

        // Another device picked something else between the deletion and this
        // device hearing about it. Timestamping the fallback "now" would sink
        // that choice — and publishing it would push the fallback over it.
        #expect(manager.storedContext.changedAt == chosenAt)
        // Including any upload the deleted choice had queued.
        #expect(!manager.pendingContextUpload)

        let elsewhere = StoredDataContext(
            context: .account(UUID()),
            changedAt: chosenAt.addingTimeInterval(1)
        )
        #expect(!manager.applySyncedContext(elsewhere))
        #expect(manager.currentContext == elsewhere.context)
    }

    @Test("A deletion is queued before anything else can persist")
    func deletionOutboxIsQueuedFirst() {
        let defaults = makeDefaults()
        let manager = makeManager(defaults: defaults)
        let account = manager.addAccount(instanceID: UUID())
        manager.setContext(.account(account.id))

        manager.removeAccount(account.id)

        // Deleting the *selected* account also corrects the context, and every
        // step of that writes storage. A crash before the tombstone was owed
        // would leave the account gone here and alive everywhere else.
        let relaunched = makeManager(defaults: defaults)
        #expect(relaunched.pendingDeletions.contains(account.id))
        #expect(relaunched.isDeleted(account.id))
        #expect(relaunched.currentContext == .local)
    }

    /// Every key the manager persists, spelled out here rather than read from
    /// it: a purge that stopped covering one of them would otherwise be
    /// invisible to these tests.
    private static let storedKeyNames = [
        "accounts", "context", "hasContext", "migrated", "pendingUploads",
        "pendingDeletions", "pendingMarkerUploads", "deletedAccounts",
        "deletedInstances", "pendingContextUpload"
    ]

    private func unresolvedKeysAreAbsent(in defaults: UserDefaults) -> Bool {
        Self.storedKeyNames.allSatisfy { defaults.object(forKey: "accounts.unresolved.\($0)") == nil }
    }

    private func makeLegacyInstance() -> Instance {
        Instance(
            type: .invidious,
            url: URL(string: "https://legacy-\(UUID().uuidString).example.com")!,
            usesAccountLogin: true
        )
    }

    @Test("An unresolved identity never migrates a legacy login")
    func unresolvedIdentityDoesNotMigrate() {
        let defaults = makeDefaults()
        let instances = InstancesManager()
        let instance = makeLegacyInstance()
        instances.add(instance)
        defer { instances.remove(instance) }

        let unresolved = AccountsManager(
            identityScope: CredentialIdentityScope(fixedScope: nil),
            instancesManager: instances,
            defaults: defaults
        )
        unresolved.reconcileLegacyAccounts()

        // Synthesizing here would file the account — and the permanent marker
        // that suppresses synthesis everywhere else — under a namespace no
        // identity ever reads back.
        #expect(unresolved.accounts.isEmpty)
        #expect(unresolved.migratedInstanceIDs.isEmpty)
        #expect(unresolved.pendingUploads.isEmpty)
        #expect(unresolved.pendingMarkerUploads.isEmpty)
        #expect(unresolvedKeysAreAbsent(in: defaults))

        // Held back, not lost: the same instance migrates as soon as there is
        // an identity to migrate it for.
        let resolved = makeManager(defaults: defaults, instances: instances)
        resolved.reconcileLegacyAccounts()
        #expect(resolved.accounts(forInstance: instance.id).count == 1)
        #expect(resolved.migratedInstanceIDs.contains(instance.id))
    }

    @Test("A scope that dips to unresolved and returns writes nothing in between")
    func scopeRoundTripLeavesTheUnresolvedNamespaceEmpty() async throws {
        let defaults = makeDefaults()
        let instances = InstancesManager()
        let instance = makeLegacyInstance()
        instances.add(instance)
        defer { instances.remove(instance) }

        let scope = CredentialIdentityScope(fixedScope: "identity-A")
        let manager = AccountsManager(
            identityScope: scope,
            instancesManager: instances,
            defaults: defaults
        )
        manager.reconcileLegacyAccounts()

        let account = try #require(manager.accounts(forInstance: instance.id).first)
        manager.setContext(.account(account.id))

        // With iCloud Drive switched off this happens on every foreground
        // activation — the scope drops and comes back as the same account.
        scope.setFixedScope(nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(manager.accounts.isEmpty)

        // Instances keep arriving over iCloud while this lasts, and each
        // arrival asks for reconciliation.
        NotificationCenter.default.post(name: .instancesDidChange, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(manager.accounts.isEmpty)
        #expect(manager.migratedInstanceIDs.isEmpty)
        // Checked here as well as after the flip back: once an identity is
        // resolved the purge would hide a write made while it was not.
        #expect(unresolvedKeysAreAbsent(in: defaults))

        scope.setFixedScope("identity-A")
        try await Task.sleep(for: .milliseconds(50))

        #expect(manager.accounts(forInstance: instance.id).map(\.id) == [account.id])
        #expect(manager.currentContext == .account(account.id))
        #expect(unresolvedKeysAreAbsent(in: defaults))
    }

    @Test("Resolving an identity purges what was stored while it was unknown")
    func resolutionPurgesTheUnresolvedNamespace() {
        let defaults = makeDefaults()

        let identityA = makeManager(defaults: defaults)
        let account = identityA.addAccount(instanceID: UUID(), displayName: "Main")

        // The blob measured on the device: a snapshot written before the
        // identity was known, contradicting the one that owns the storage.
        let unresolved = AccountsManager(
            identityScope: CredentialIdentityScope(fixedScope: nil),
            defaults: defaults
        )
        let stale = unresolved.addAccount(instanceID: UUID())
        unresolved.setContext(.account(stale.id))
        #expect(defaults.data(forKey: "accounts.unresolved.accounts") != nil)

        let relaunched = makeManager(defaults: defaults)

        #expect(unresolvedKeysAreAbsent(in: defaults))
        #expect(relaunched.account(id: account.id)?.displayName == "Main")
        #expect(relaunched.account(id: stale.id) == nil)
    }

    @Test("A save made while the namespace is reloading is dropped")
    func saveDuringTheReloadGapIsDropped() async throws {
        let defaults = makeDefaults()
        let scope = CredentialIdentityScope(fixedScope: "identity-A")
        let manager = AccountsManager(identityScope: scope, defaults: defaults)
        let account = manager.addAccount(instanceID: UUID())

        // The scope moves before the observer that reloads this manager runs,
        // so `namespace` already names the new identity while everything in
        // memory is still the previous one's.
        scope.setFixedScope("identity-B", announcing: false)
        manager.setContext(.account(account.id))

        // identity-B must not be handed identity-A's selection...
        #expect(defaults.data(forKey: "accounts.identity-B.context") == nil)
        #expect(!defaults.bool(forKey: "accounts.identity-B.hasContext"))

        // ...and identity-A's stored copy must not have moved either: the write
        // was aimed at keys that no longer describe what is in memory.
        let storedA = try #require(defaults.data(forKey: "accounts.identity-A.context"))
        #expect(try JSONDecoder().decode(StoredDataContext.self, from: storedA).context == .local)

        // The announced flip is the real path, and it reloads cleanly.
        scope.setFixedScope("identity-A")
        try await Task.sleep(for: .milliseconds(50))

        #expect(manager.accounts.map(\.id) == [account.id])
        #expect(manager.currentContext == .local)
    }

    @Test("A migrated context loses to any explicit choice")
    func migratedContextLosesToExplicitChoice() {
        let manager = makeManager()
        let accountID = UUID()

        // A migration is a guess at intent, stamped at the epoch so an explicit
        // choice on any device outranks it regardless of arrival order.
        let migrated = StoredDataContext.migrated(.account(accountID))
        #expect(migrated.isMigrated)

        manager.setContext(.local)
        manager.applySyncedContext(migrated)
        #expect(manager.currentContext == .local)
    }
}

@Suite("DataContext validation", .serialized)
@MainActor
struct DataContextValidatorTests {
    private func makeValidator(
        instances: InstancesManager,
        defaults: UserDefaults? = nil
    ) -> (AccountsManager, DataContextValidator) {
        let accounts = AccountsManager(
            identityScope: CredentialIdentityScope(fixedScope: "identity-A"),
            instancesManager: instances,
            defaults: defaults ?? UserDefaults(suiteName: "yattee.tests.\(UUID().uuidString)")!
        )
        let validator = DataContextValidator(
            accountsManager: accounts,
            instancesManager: instances,
            toastManager: ToastManager()
        )
        return (accounts, validator)
    }

    @Test("A switched-off instance makes its context unavailable, not removed")
    func disabledInstanceIsUnavailable() {
        let instances = InstancesManager()
        var instance = Instance(type: .invidious, url: URL(string: "https://inv.example.com")!)
        instances.add(instance)

        let (accounts, validator) = makeValidator(instances: instances)
        let account = accounts.addAccount(instanceID: instance.id)
        accounts.setStatus(.signedIn, for: account.id)
        accounts.setContext(.account(account.id))

        #expect(validator.validity == .valid)

        // Disabling the instance leaves the account signed in, so nothing about
        // the account itself says the server may no longer be used.
        instance.isEnabled = false
        instances.update(instance)

        #expect(validator.validity == .temporarilyUnavailable(.instanceDisabled))
        // The user's selection is kept — turning the instance back on restores
        // it without them having to choose again.
        #expect(accounts.currentContext == .account(account.id))
        #expect(validator.effectiveContext == .local)
        #expect(!validator.allowsServerMutations)

        instances.remove(instance)
    }

    @Test("Only a deletion the app can point at moves the context")
    func correctionRequiresATombstone() {
        let instances = InstancesManager()
        var instance = Instance(type: .invidious, url: URL(string: "https://inv-correct.example.com")!)
        instances.add(instance)
        defer { instances.remove(instance) }

        let defaults = UserDefaults(suiteName: "yattee.tests.\(UUID().uuidString)")!
        let (accounts, validator) = makeValidator(instances: instances, defaults: defaults)
        let account = accounts.addAccount(instanceID: instance.id)
        accounts.setStatus(.signedIn, for: account.id)
        accounts.setContext(.account(account.id))

        // Unusable, but the account is still there — the user gets it back by
        // switching the instance on again, so nothing may be corrected.
        instance.isEnabled = false
        instances.update(instance)
        validator.correctIfContextRemoved()
        #expect(accounts.currentContext == .account(account.id))

        instance.isEnabled = true
        instances.update(instance)
        accounts.setStatus(.credentialMissing, for: account.id)
        validator.correctIfContextRemoved()
        #expect(accounts.currentContext == .account(account.id))

        // An account the store has never heard of has not been proven deleted:
        // it may be a record the fetch has yet to deliver, and this runs on
        // foreground activation — before that fetch.
        let pending = UUID()
        accounts.setContext(.account(pending))
        validator.correctIfContextRemoved()
        #expect(accounts.currentContext == .account(pending))

        // Nor is it corrected on the way back in: a relaunch reads the same
        // absence, and the user's choice has to survive it.
        let (reloaded, reloadedValidator) = makeValidator(instances: instances, defaults: defaults)
        reloadedValidator.correctIfContextRemoved()
        #expect(reloaded.currentContext == .account(pending))
    }

    @Test("A tombstoned selection is repaired without being published")
    func correctionFollowsTheTombstone() {
        let instances = InstancesManager()
        let instance = Instance(type: .invidious, url: URL(string: "https://inv-tombstone.example.com")!)
        instances.add(instance)
        defer { instances.remove(instance) }

        let (accounts, validator) = makeValidator(instances: instances)
        let deleted = accounts.addAccount(instanceID: instance.id)
        let sibling = accounts.addAccount(instanceID: instance.id)
        accounts.setStatus(.signedIn, for: sibling.id)

        // Deleted while this device pointed somewhere else, then selected again
        // by a stale choice that arrived afterwards — the case the deletion
        // paths themselves never see.
        accounts.setContext(.local)
        accounts.applyRemoteTombstone(deleted.id)
        accounts.setContext(.account(deleted.id))
        let chosenAt = accounts.storedContext.changedAt

        validator.correctIfContextRemoved()

        // Repaired like any deletion: the signed-in login on the same server,
        // the replaced choice's timestamp, and nothing left to publish.
        #expect(accounts.currentContext == .account(sibling.id))
        #expect(accounts.storedContext.changedAt == chosenAt)
        #expect(!accounts.pendingContextUpload)
    }

    @Test("Nothing is repaired while the namespace is reloading")
    func correctionIsFencedToTheLoadedNamespace() {
        let instances = InstancesManager()
        let instance = Instance(type: .invidious, url: URL(string: "https://inv-reload.example.com")!)
        instances.add(instance)
        defer { instances.remove(instance) }

        let scope = CredentialIdentityScope(fixedScope: "identity-A")
        let toasts = ToastManager()
        let accounts = AccountsManager(
            identityScope: scope,
            instancesManager: instances,
            defaults: UserDefaults(suiteName: "yattee.tests.\(UUID().uuidString)")!
        )
        let validator = DataContextValidator(
            accountsManager: accounts,
            instancesManager: instances,
            toastManager: toasts
        )

        let deleted = accounts.addAccount(instanceID: instance.id)
        let sibling = accounts.addAccount(instanceID: instance.id)
        accounts.setStatus(.signedIn, for: sibling.id)
        accounts.setContext(.local)
        accounts.applyRemoteTombstone(deleted.id)
        accounts.setContext(.account(deleted.id))

        // The scope moved before the observer that reloads the manager ran, so
        // the selection and the tombstone are both still identity-A's — and the
        // identity now resolved is identity-B, which chose neither.
        scope.setFixedScope("identity-B", announcing: false)
        validator.correctIfContextRemoved()

        #expect(accounts.currentContext == .account(deleted.id))
        // Least of all announced: a toast here tells the user their account was
        // switched during a reload that has not shown them an account yet.
        #expect(toasts.activeToasts.isEmpty)

        // Back under the namespace the state in memory came from, the same
        // repair runs exactly as it always did.
        scope.setFixedScope("identity-A", announcing: false)
        validator.correctIfContextRemoved()

        #expect(accounts.currentContext == .account(sibling.id))
        #expect(!toasts.activeToasts.isEmpty)
    }

    @Test("Only accounts the app can actually resolve are offered")
    func availableContextsAreFiltered() {
        let instances = InstancesManager()
        let enabled = Instance(type: .invidious, url: URL(string: "https://inv-a.example.com")!)
        let disabled = Instance(type: .invidious, url: URL(string: "https://inv-b.example.com")!, isEnabled: false)
        // No account concept on PeerTube, so a context there could never be
        // served from.
        let unsupported = Instance(type: .peertube, url: URL(string: "https://pt.example.com")!)
        for instance in [enabled, disabled, unsupported] { instances.add(instance) }
        defer { for instance in [enabled, disabled, unsupported] { instances.remove(instance) } }

        let (accounts, validator) = makeValidator(instances: instances)
        let usable = accounts.addAccount(instanceID: enabled.id)
        _ = accounts.addAccount(instanceID: disabled.id)
        _ = accounts.addAccount(instanceID: unsupported.id)
        // An account whose instance has not synced yet has no known
        // capabilities, which is not the same as having none.
        _ = accounts.addAccount(instanceID: UUID())

        #expect(validator.availableContexts == [.local, .account(usable.id)])
    }
}

@Suite("Data context repair", .serialized)
@MainActor
struct DataContextRepairTests {
    private func makeInstance(_ host: String) -> Instance {
        Instance(type: .invidious, url: URL(string: "https://\(host)-\(UUID().uuidString).example.com")!)
    }

    private func makeManager(
        instances: InstancesManager,
        defaults: UserDefaults? = nil
    ) -> AccountsManager {
        AccountsManager(
            identityScope: CredentialIdentityScope(fixedScope: "identity-A"),
            instancesManager: instances,
            defaults: defaults ?? UserDefaults(suiteName: "yattee.tests.\(UUID().uuidString)")!
        )
    }

    @Test("Deleting the selected account falls back to a signed-in sibling")
    func deletionPrefersSignedInSibling() {
        let instances = InstancesManager()
        let instance = makeInstance("inv")
        instances.add(instance)
        defer { instances.remove(instance) }

        let manager = makeManager(instances: instances)
        let selected = manager.addAccount(instanceID: instance.id)
        let sibling = manager.addAccount(instanceID: instance.id)
        manager.setStatus(.signedIn, for: sibling.id)
        manager.setContext(.account(selected.id))

        let chosenAt = manager.storedContext.changedAt
        manager.removeAccount(selected.id)

        #expect(manager.currentContext == .account(sibling.id))
        // A repair, not a choice: it keeps the replaced selection's timestamp
        // and is never published.
        #expect(manager.storedContext.changedAt == chosenAt)
        #expect(!manager.pendingContextUpload)
    }

    @Test("Without a signed-in sibling the repair lands on local")
    func deletionWithoutSiblingFallsBackToLocal() {
        let instances = InstancesManager()
        let instance = makeInstance("inv")
        instances.add(instance)
        defer { instances.remove(instance) }

        let manager = makeManager(instances: instances)
        let selected = manager.addAccount(instanceID: instance.id)
        // Present but not usable here — a context pointing at it would fall
        // straight back to local data anyway.
        let sibling = manager.addAccount(instanceID: instance.id)
        manager.setStatus(.credentialMissing, for: sibling.id)
        manager.setContext(.account(selected.id))

        manager.removeAccount(selected.id)

        #expect(manager.currentContext == .local)
        #expect(!manager.pendingContextUpload)
    }

    @Test("A repair made while a sibling was still being checked never comes back")
    func repairIsNotReconsideredWhenStatusesSettle() {
        let instances = InstancesManager()
        let instance = makeInstance("inv")
        instances.add(instance)
        defer { instances.remove(instance) }

        let manager = makeManager(instances: instances)
        let selected = manager.addAccount(instanceID: instance.id)
        let sibling = manager.addAccount(instanceID: instance.id)
        // Nothing is known about the sibling yet, so it cannot be repaired
        // onto: `checking` is the absence of an answer, not a usable login.
        manager.setStatus(.checking, for: sibling.id)
        manager.setContext(.account(selected.id))

        manager.removeAccount(selected.id)
        #expect(manager.currentContext == .local)

        // Statuses settling afterwards is not a second chance. The selection no
        // longer names an account, so the tombstone repair has nothing left to
        // act on and local is where the user stays — which is why foreground
        // activation refreshes statuses *before* it lets a tombstone move
        // anything, rather than repairing twice.
        manager.setStatus(.signedIn, for: sibling.id)

        #expect(!manager.correctContextIfAccountDeleted())
        #expect(manager.currentContext == .local)
    }

    @Test("A signed-in account on another server is never the repair")
    func repairNeverCrossesInstances() {
        let instances = InstancesManager()
        let first = makeInstance("inv-first")
        let second = makeInstance("inv-second")
        instances.add(first)
        instances.add(second)
        defer {
            instances.remove(first)
            instances.remove(second)
        }

        let manager = makeManager(instances: instances)
        let selected = manager.addAccount(instanceID: first.id)
        let elsewhere = manager.addAccount(instanceID: second.id)
        manager.setStatus(.signedIn, for: elsewhere.id)
        manager.setContext(.account(selected.id))

        manager.removeAccount(selected.id)

        #expect(manager.currentContext == .local)
    }

    @Test("A synced context naming a deleted account repairs to its sibling")
    func syncedTombstoneRepairPrefersSibling() {
        let instances = InstancesManager()
        let instance = makeInstance("inv")
        instances.add(instance)
        defer { instances.remove(instance) }

        let manager = makeManager(instances: instances)
        let deleted = manager.addAccount(instanceID: instance.id)
        let sibling = manager.addAccount(instanceID: instance.id)
        manager.setStatus(.signedIn, for: sibling.id)

        manager.setContext(.local)
        manager.removeAccount(deleted.id)

        // Another device selected the account before it heard about the
        // deletion, and stamped that choice later than anything here.
        let incoming = StoredDataContext(
            context: .account(deleted.id),
            changedAt: Date().addingTimeInterval(60)
        )
        manager.applySyncedContext(incoming)

        #expect(manager.currentContext == .account(sibling.id))
    }

    @Test("A synced context for a deleted account with no sibling lands on local")
    func syncedTombstoneRepairFallsBackToLocal() {
        let instances = InstancesManager()
        let instance = makeInstance("inv")
        instances.add(instance)
        defer { instances.remove(instance) }

        let manager = makeManager(instances: instances)
        let deleted = manager.addAccount(instanceID: instance.id)

        manager.setContext(.local)
        manager.removeAccount(deleted.id)

        let incoming = StoredDataContext(
            context: .account(deleted.id),
            changedAt: Date().addingTimeInterval(60)
        )
        manager.applySyncedContext(incoming)

        #expect(manager.currentContext == .local)
    }

    @Test("Adopting a repaired synced context drops what the replaced choice owed")
    func syncedTombstoneRepairIsNeverPublished() {
        let instances = InstancesManager()
        let instance = makeInstance("inv")
        instances.add(instance)
        defer { instances.remove(instance) }

        let manager = makeManager(instances: instances)
        let deleted = manager.addAccount(instanceID: instance.id)
        let sibling = manager.addAccount(instanceID: instance.id)
        manager.setStatus(.signedIn, for: sibling.id)

        // A choice made here that has not reached the server yet.
        manager.setContext(.local)
        manager.removeAccount(deleted.id)
        #expect(manager.pendingContextUpload)

        let incoming = StoredDataContext(
            context: .account(deleted.id),
            changedAt: Date().addingTimeInterval(60)
        )
        manager.applySyncedContext(incoming)

        // The repair replaced that choice, so the upload it owed goes with it —
        // sending it now would publish the fallback under its timestamp.
        #expect(manager.currentContext == .account(sibling.id))
        #expect(!manager.pendingContextUpload)
    }

    @Test("A local choice that outranks a repair keeps its upload")
    func repairThatLosesLeavesTheChoiceDirty() {
        let instances = InstancesManager()
        let instance = makeInstance("inv")
        instances.add(instance)
        defer { instances.remove(instance) }

        let manager = makeManager(instances: instances)
        let deleted = manager.addAccount(instanceID: instance.id)
        let sibling = manager.addAccount(instanceID: instance.id)
        manager.setStatus(.signedIn, for: sibling.id)

        manager.removeAccount(deleted.id)
        manager.setContext(.local)

        // The other device's selection — and so its repair — is older than the
        // choice made here.
        let incoming = StoredDataContext(
            context: .account(deleted.id),
            changedAt: Date().addingTimeInterval(-60)
        )
        #expect(manager.applySyncedContext(incoming))

        #expect(manager.currentContext == .local)
        #expect(manager.pendingContextUpload)
    }

    @Test("A repair is never pushed back over the server's older context")
    func repairIsNeverPushedBackOverAnOlderContext() {
        let instances = InstancesManager()
        let instance = makeInstance("inv")
        instances.add(instance)
        defer { instances.remove(instance) }

        let defaults = UserDefaults(suiteName: "yattee.tests.\(UUID().uuidString)")!
        let manager = makeManager(instances: instances, defaults: defaults)
        let selected = manager.addAccount(instanceID: instance.id)
        let sibling = manager.addAccount(instanceID: instance.id)
        manager.setStatus(.signedIn, for: sibling.id)

        manager.setContext(.account(selected.id))
        let chosenAt = manager.storedContext.changedAt
        manager.confirmContextUpload(changedAt: chosenAt)
        #expect(!manager.pendingContextUpload)

        // One fetch carrying both: the tombstone repairs the selection, keeping
        // the deleted choice's timestamp, and the older context the server still
        // holds arrives right behind it.
        manager.applyRemoteTombstone(selected.id)
        #expect(manager.currentContext == .account(sibling.id))

        let older = StoredDataContext(context: .local, changedAt: chosenAt.addingTimeInterval(-60))
        #expect(!manager.applySyncedContext(older))

        // The repair only outranked the server's copy because it inherited that
        // timestamp. Publishing it would put a fallback nobody chose over an
        // explicit choice, so the explicit value is taken as it stands instead —
        // and nothing is sent.
        #expect(manager.currentContext == .local)
        #expect(manager.storedContext.changedAt == older.changedAt)
        #expect(!manager.pendingContextUpload)

        // What was adopted is a choice, so it publishes like one when this
        // device later has the newer copy.
        let reloaded = makeManager(instances: instances, defaults: defaults)
        #expect(!reloaded.applySyncedContext(older))
        #expect(!reloaded.pendingContextUpload)

        reloaded.setContext(.account(sibling.id))
        #expect(reloaded.applySyncedContext(older))
        #expect(reloaded.pendingContextUpload)
    }

    @Test("A repair read back from disk still yields rather than publishing")
    func reloadedRepairStillYieldsToTheServersContext() {
        let instances = InstancesManager()
        let instance = makeInstance("inv")
        instances.add(instance)
        defer { instances.remove(instance) }

        let defaults = UserDefaults(suiteName: "yattee.tests.\(UUID().uuidString)")!
        let manager = makeManager(instances: instances, defaults: defaults)
        let selected = manager.addAccount(instanceID: instance.id)
        let sibling = manager.addAccount(instanceID: instance.id)
        manager.setStatus(.signedIn, for: sibling.id)

        manager.setContext(.account(selected.id))
        let chosenAt = manager.storedContext.changedAt
        manager.confirmContextUpload(changedAt: chosenAt)
        manager.applyRemoteTombstone(selected.id)
        #expect(manager.currentContext == .account(sibling.id))

        // Relaunched before any record arrives: without the repair surviving on
        // disk this reads as a choice, and the stale record below would be
        // pushed back over rather than adopted.
        let reloaded = makeManager(instances: instances, defaults: defaults)
        reloaded.setStatus(.signedIn, for: sibling.id)
        #expect(reloaded.currentContext == .account(sibling.id))

        let older = StoredDataContext(context: .local, changedAt: chosenAt.addingTimeInterval(-60))
        #expect(!reloaded.applySyncedContext(older))

        #expect(reloaded.currentContext == .local)
        #expect(!reloaded.pendingContextUpload)
    }

    @Test("A repair yields to an explicit context it ties with")
    func repairYieldsToAnExplicitContextOnATie() {
        let instances = InstancesManager()
        let instance = makeInstance("inv")
        instances.add(instance)
        defer { instances.remove(instance) }

        let manager = makeManager(instances: instances)
        let selected = manager.addAccount(instanceID: instance.id)
        let sibling = manager.addAccount(instanceID: instance.id)
        manager.setStatus(.signedIn, for: sibling.id)

        manager.setContext(.account(selected.id))
        let chosenAt = manager.storedContext.changedAt
        manager.confirmContextUpload(changedAt: chosenAt)
        manager.applyRemoteTombstone(selected.id)
        #expect(manager.currentContext == .account(sibling.id))

        // Exactly the same instant — which two migrated contexts always are,
        // both being stamped at the epoch. The tie-break settles it against the
        // incoming value, so the repair is neither outranked nor pushed back and
        // would otherwise stand against the server's choice forever.
        let tied = StoredDataContext(context: .local, changedAt: chosenAt)
        #expect(!manager.applySyncedContext(tied))

        #expect(manager.currentContext == .local)
        #expect(!manager.pendingContextUpload)
    }

    @Test("A repair yields to an older context naming an account that is still there")
    func repairYieldsToAnOlderContextNamingALiveAccount() {
        let instances = InstancesManager()
        let instance = makeInstance("inv")
        instances.add(instance)
        defer { instances.remove(instance) }

        let manager = makeManager(instances: instances)
        let selected = manager.addAccount(instanceID: instance.id)
        let sibling = manager.addAccount(instanceID: instance.id)
        let other = manager.addAccount(instanceID: instance.id)
        manager.setStatus(.signedIn, for: sibling.id)

        manager.setContext(.account(selected.id))
        let chosenAt = manager.storedContext.changedAt
        manager.confirmContextUpload(changedAt: chosenAt)
        manager.applyRemoteTombstone(selected.id)
        #expect(manager.currentContext == .account(sibling.id))

        let older = StoredDataContext(
            context: .account(other.id),
            changedAt: chosenAt.addingTimeInterval(-60)
        )
        #expect(!manager.applySyncedContext(older))

        // Somebody chose that account; the sibling was picked by this device's
        // own statuses. Adopting it is what re-converges the devices, and it is
        // still not a reason to send anything.
        #expect(manager.currentContext == .account(other.id))
        #expect(!manager.pendingContextUpload)
    }

    @Test("An older context naming the deleted account repairs again rather than landing on it")
    func repairYieldsToAnOlderContextNamingTheDeletedAccount() {
        let instances = InstancesManager()
        let instance = makeInstance("inv")
        instances.add(instance)
        defer { instances.remove(instance) }

        let manager = makeManager(instances: instances)
        let selected = manager.addAccount(instanceID: instance.id)
        let sibling = manager.addAccount(instanceID: instance.id)
        manager.setStatus(.signedIn, for: sibling.id)

        manager.setContext(.account(selected.id))
        let chosenAt = manager.storedContext.changedAt
        manager.confirmContextUpload(changedAt: chosenAt)
        manager.applyRemoteTombstone(selected.id)

        // The server still holds the choice the tombstone killed. Yielding to it
        // means yielding to what it repairs to, so the result is the repair
        // again — and it is still a repair, so it still never publishes.
        let older = StoredDataContext(
            context: .account(selected.id),
            changedAt: chosenAt.addingTimeInterval(-60)
        )
        #expect(!manager.applySyncedContext(older))

        #expect(manager.currentContext == .account(sibling.id))
        // Yielded rather than held onto: the borrowed timestamp goes back to
        // what the server holds, so this device stops out-ranking it.
        #expect(manager.storedContext.changedAt == older.changedAt)
        #expect(manager.storedContextIsRepair)
        #expect(!manager.pendingContextUpload)
    }

    @Test("A repair recomputes statuses before it picks a sibling")
    func repairRefreshesStatusesBeforeChoosing() {
        let instances = InstancesManager()
        let instance = makeInstance("inv")
        instances.add(instance)
        defer { instances.remove(instance) }

        let manager = makeManager(instances: instances)
        let selected = manager.addAccount(instanceID: instance.id)
        let sibling = manager.addAccount(instanceID: instance.id)
        // The sibling's credential arrived over iCloud Keychain while the app
        // was in the background. Nothing that recomputes statuses ran, so it
        // still reads as signed out.
        manager.setStatus(.credentialMissing, for: sibling.id)
        manager.setContext(.account(selected.id))

        var refreshes = 0
        manager.refreshStatusesForRepair = { [weak manager] in
            refreshes += 1
            manager?.setStatus(.signedIn, for: sibling.id)
        }

        // A tombstone delivered by a silent push, with no foreground activation
        // to sequence the refresh ahead of it.
        manager.applyRemoteTombstone(selected.id)

        #expect(refreshes == 1)
        #expect(manager.currentContext == .account(sibling.id))
    }

    @Test("An account dominated by a tombstone still says where it lived")
    func discardedAccountKeepsItsInstanceForRepair() {
        let instances = InstancesManager()
        let instance = makeInstance("inv")
        instances.add(instance)
        defer { instances.remove(instance) }

        let manager = makeManager(instances: instances)
        let sibling = manager.addAccount(instanceID: instance.id)
        manager.setStatus(.signedIn, for: sibling.id)

        // A device that meets the tombstone before the account it kills has
        // nothing to read the instance off — the map entry cannot be made then.
        let deleted = Account(instanceID: instance.id)
        manager.applyRemoteTombstone(deleted.id)
        #expect(manager.deletedAccountInstanceIDs[deleted.id] == nil)

        // The dominated record that follows is the only thing that still knows.
        manager.applySyncedAccount(deleted)
        #expect(manager.account(id: deleted.id) == nil)
        #expect(manager.deletedAccountInstanceIDs[deleted.id] == instance.id)

        // Which is what lets the context naming it land on the sibling instead
        // of falling all the way back to local.
        manager.applySyncedContext(
            StoredDataContext(context: .account(deleted.id), changedAt: Date())
        )
        #expect(manager.currentContext == .account(sibling.id))
    }
}

@Suite("Account capabilities")
@MainActor
struct AccountCapabilitiesTests {
    @Test("Backend capabilities match the documented API surface")
    func capabilitiesPerBackend() {
        let invidious = InstanceType.invidious.accountCapabilities
        #expect(invidious.supportsWatchHistory)
        #expect(invidious.supportsPlaylistPrivacy)
        #expect(invidious.supportsPlaylistWrites)

        // Piped has no history endpoint at all and no playlist privacy.
        let piped = InstanceType.piped.accountCapabilities
        #expect(piped.supportsPlaylistWrites)
        #expect(!piped.supportsWatchHistory)
        #expect(!piped.supportsPlaylistPrivacy)

        // No account concept on either of these today.
        #expect(!InstanceType.peertube.accountCapabilities.isSelectableContext)
        #expect(!InstanceType.yatteeServer.accountCapabilities.isSelectableContext)
    }
}

@Suite("DataContext legacy migration")
@MainActor
struct DataContextMigrationTests {
    @Test("Legacy subscription accounts map onto contexts")
    func legacyMappingIsIdentity() {
        let instanceID = UUID()

        #expect(DataContext(legacy: .local) == .local)

        // Migrated accounts reuse their instance UUID, so this is an identity
        // mapping rather than a lookup that could fail.
        #expect(DataContext(legacy: .invidious(instanceID)) == .account(instanceID))
        #expect(DataContext(legacy: .piped(instanceID)) == .account(instanceID))
    }

    @Test("A legacy account without an instance falls back to local")
    func legacyWithoutInstanceIsLocal() {
        let malformed = SubscriptionAccount(type: .invidious, instanceID: nil)
        #expect(DataContext(legacy: malformed) == .local)
    }
}
