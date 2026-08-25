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
        instances: InstancesManager
    ) -> (AccountsManager, DataContextValidator) {
        let accounts = AccountsManager(
            identityScope: CredentialIdentityScope(fixedScope: "identity-A"),
            instancesManager: instances,
            defaults: UserDefaults(suiteName: "yattee.tests.\(UUID().uuidString)")!
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
