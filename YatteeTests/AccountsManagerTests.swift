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
