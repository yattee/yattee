//
//  AccountsScreenTests.swift
//  YatteeTests
//
//  The accounts screen's two pieces of logic that are not presentation:
//  removing an account whose source is gone, and disclosing what deleting a
//  source takes with it.
//

import Testing
import Foundation
import SwiftUI
@testable import Yattee

@Suite("Orphaned account removal")
@MainActor
struct OrphanedAccountRemovalTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "yattee.tests.\(UUID().uuidString)")!
    }

    private func makeScope() -> CredentialIdentityScope {
        CredentialIdentityScope(fixedScope: "identity-\(UUID().uuidString)")
    }

    private func makeInstance(_ type: InstanceType) -> Instance {
        Instance(type: type, url: URL(string: "https://\(UUID().uuidString).example.com")!)
    }

    @Test("An account outlives its source, and knows nothing about it")
    func orphanHasNothingToResolveThrough() {
        let scope = makeScope()
        let instances = makeTestInstancesManager()
        let instance = makeInstance(.invidious)
        instances.add(instance)

        let accountsManager = AccountsManager(
            identityScope: scope,
            instancesManager: instances,
            defaults: makeDefaults()
        )
        let account = accountsManager.addAccount(instanceID: instance.id)

        instances.remove(instance)

        // Everything the ordinary cascade resolves through is gone with it —
        // which is why removal has to go by account ID rather than by instance.
        #expect(accountsManager.instance(for: account) == nil)
        #expect(accountsManager.capabilities(for: account) == nil)
        #expect(accountsManager.orphanedAccounts.contains { $0.id == account.id })
        #expect(!accountsManager.selectableAccounts.contains { $0.id == account.id })

        accountsManager.removeAccount(account.id)
    }

    @Test("Removing an orphan deletes the credential filed under its ID")
    func removalDeletesTheCredential() {
        let scope = makeScope()
        let invidious = InvidiousCredentialsManager(identityScope: scope)
        let piped = PipedCredentialsManager(identityScope: scope)

        let instances = makeTestInstancesManager()
        let instance = makeInstance(.invidious)
        instances.add(instance)

        let accountsManager = AccountsManager(
            identityScope: scope,
            instancesManager: instances,
            defaults: makeDefaults()
        )
        let account = accountsManager.addAccount(instanceID: instance.id)
        invidious.setCredential("sid-1", for: account)
        #expect(invidious.credential(for: account) != nil)

        instances.remove(instance)

        var discarded: [UUID] = []
        AccountRemoval.removeOrphan(
            account.id,
            stores: [invidious, piped],
            accountsManager: accountsManager,
            discardData: { discarded.append($0) }
        )

        #expect(invidious.credential(for: account) == nil)
        #expect(accountsManager.account(id: account.id) == nil)
        #expect(!accountsManager.orphanedAccounts.contains { $0.id == account.id })
        // The in-memory data goes too, or the account's subscriptions and
        // playlists keep answering for an account nobody has.
        #expect(discarded == [account.id])
    }

    @Test("Every store is asked, because the backend is no longer knowable")
    func removalAsksBothStores() {
        let scope = makeScope()
        let invidious = InvidiousCredentialsManager(identityScope: scope)
        let piped = PipedCredentialsManager(identityScope: scope)

        let instances = makeTestInstancesManager()
        let instance = makeInstance(.piped)
        instances.add(instance)

        let accountsManager = AccountsManager(
            identityScope: scope,
            instancesManager: instances,
            defaults: makeDefaults()
        )
        let account = accountsManager.addAccount(instanceID: instance.id)
        piped.setCredential("token-1", for: account)

        instances.remove(instance)

        AccountRemoval.removeOrphan(
            account.id,
            stores: [invidious, piped],
            accountsManager: accountsManager,
            discardData: { _ in }
        )

        // The instance's type is what said which store to look in, and it is
        // gone — so a Piped orphan must be cleared by a caller that cannot know
        // it was Piped.
        #expect(piped.credential(for: account) == nil)
    }

    @Test("A deletion queued for the server survives the removal")
    func removalQueuesTheTombstone() {
        let scope = makeScope()
        let instances = makeTestInstancesManager()
        let instance = makeInstance(.invidious)
        instances.add(instance)

        let accountsManager = AccountsManager(
            identityScope: scope,
            instancesManager: instances,
            defaults: makeDefaults()
        )
        let account = accountsManager.addAccount(instanceID: instance.id)

        instances.remove(instance)

        AccountRemoval.removeOrphan(
            account.id,
            stores: [],
            accountsManager: accountsManager,
            discardData: { _ in }
        )

        // Removing an orphan is a real deletion, not a local tidy-up: without
        // the tombstone every other device would keep the account and send it
        // back.
        #expect(accountsManager.pendingDeletions.contains(account.id))
    }

    @Test("The deletion is durable before the secret is destroyed")
    func removalRecordsTheTombstoneFirst() {
        let scope = makeScope()
        let instances = makeTestInstancesManager()
        let instance = makeInstance(.invidious)
        instances.add(instance)

        let accountsManager = AccountsManager(
            identityScope: scope,
            instancesManager: instances,
            defaults: makeDefaults()
        )
        let account = accountsManager.addAccount(instanceID: instance.id)

        instances.remove(instance)

        let store = DeletionOrderStore(accountsManager: accountsManager)
        AccountRemoval.removeOrphan(
            account.id,
            stores: [store],
            accountsManager: accountsManager,
            discardData: { _ in }
        )

        // A crash in between would otherwise bring the account back on the next
        // launch — signed out, with no deletion owed to any other device.
        #expect(store.tombstoneWhenDeleted[account.id] == true)
    }

    @Test("The pre-revamp instance-keyed item is deliberately left alone")
    func removalLeavesTheLegacyItem() {
        let scope = makeScope()
        let invidious = InvidiousCredentialsManager(identityScope: scope)

        let instances = makeTestInstancesManager()
        let instance = makeInstance(.invidious)
        instances.add(instance)

        let accountsManager = AccountsManager(
            identityScope: scope,
            instancesManager: instances,
            defaults: makeDefaults()
        )
        let account = accountsManager.addAccount(instanceID: instance.id)

        // The unscoped legacy item is keyed by the instance, and identifying it
        // needs the instance — which is exactly what an orphan is missing.
        invidious.setCredential("legacy-sid", for: instance)
        defer { invidious.deleteCredential(for: instance) }

        instances.remove(instance)

        AccountRemoval.removeOrphan(
            account.id,
            stores: [invidious],
            accountsManager: accountsManager,
            discardData: { _ in }
        )

        #expect(invidious.credential(for: instance) == "legacy-sid")
    }
}

/// A credential store that records what the account manager already knew at the
/// moment it was asked to destroy a secret.
///
/// The ordering is the whole point of the cascade and cannot be observed from
/// its outcome — both orders end in the same state unless the process dies
/// halfway.
@Observable
@MainActor
private final class DeletionOrderStore: AccountCredentialsManager {
    private let accountsManager: AccountsManager
    var tombstoneWhenDeleted: [UUID: Bool] = [:]

    init(accountsManager: AccountsManager) {
        self.accountsManager = accountsManager
    }

    var loggedInAccountIDs: Set<UUID> { [] }
    var isScopeResolved: Bool { true }

    func setCredential(_: String, for _: Account) {}
    func credential(for _: Account) -> String? { nil }
    func deleteCredential(for account: Account) { deleteCredential(forAccountID: account.id) }

    func deleteCredential(forAccountID accountID: UUID) {
        tombstoneWhenDeleted[accountID] = accountsManager.isDeleted(accountID)
            && accountsManager.pendingDeletions.contains(accountID)
    }

    func resyncCredentialsWithCurrentSetting() {}
    func setUsername(_: String, for _: Account) {}
    func username(for _: Account) -> String? { nil }
    func isLoggedIn(for _: Account) -> Bool { false }
    func refreshLoginStatus(for _: Account) {}
    func hasAdoptableLegacyCredential(for _: Account) -> Bool { false }
    @discardableResult func adoptLegacyCredential(for _: Account) -> Bool { false }
    func deleteLegacyCredentialIfOwned(for _: Account) {}
}

@Suite("Instance deletion disclosure")
struct InstanceDeletionDisclosureTests {
    @Test("A source with no accounts adds nothing to the question")
    func noAccountsSaysNothing() {
        #expect(InstanceDeletionDisclosure.message(accountNames: []) == nil)
    }

    @Test("A single account is counted and named")
    func oneAccountIsNamed() throws {
        let message = try #require(InstanceDeletionDisclosure.message(accountNames: ["me@inv.example.com"]))

        #expect(message.contains("me@inv.example.com"))
        #expect(message.contains("1"))
        // The lead-in would leak its key if the plural variation were malformed.
        #expect(!message.contains("accountsWarning"))
    }

    @Test("Several accounts are counted and all named, one per line")
    func severalAccountsAreNamed() throws {
        let names = ["first@inv.example.com", "second@inv.example.com", "third@inv.example.com"]
        let message = try #require(InstanceDeletionDisclosure.message(accountNames: names))

        for name in names {
            #expect(message.contains(name))
        }
        #expect(message.contains("3"))
        #expect(message.split(separator: "\n").count == names.count + 1)
    }

    @Test("The count reads differently for one than for many")
    func countVariesWithTheNumberOfAccounts() throws {
        let single = try #require(InstanceDeletionDisclosure.message(accountNames: ["a"]))
        let several = try #require(InstanceDeletionDisclosure.message(accountNames: ["a", "b"]))

        let singleLeadIn = try #require(single.split(separator: "\n").first)
        let severalLeadIn = try #require(several.split(separator: "\n").first)

        #expect(singleLeadIn != severalLeadIn)
    }
}

@Suite("Account status badge")
struct AccountStatusBadgeTests {
    @Test("Every status is named, and no two the same")
    func statusesAreNamed() {
        let statuses: [AccountStatus] = [
            .checking, .signedIn, .credentialMissing, .credentialRejected, .unreachable
        ]
        let texts = statuses.map { AccountStatusBadge.text(for: $0) }

        #expect(texts.allSatisfy { !$0.isEmpty })
        #expect(Set(texts).count == statuses.count)
    }

    @Test("Only the states the user has to act on are coloured")
    func onlyActionableStatesAreColoured() {
        #expect(AccountStatusBadge.color(for: .credentialRejected) == .red)
        #expect(AccountStatusBadge.color(for: .unreachable) == .orange)

        // A credential that never arrived on this device is ordinary — tvOS
        // never receives them at all — so it must not read as a fault.
        #expect(AccountStatusBadge.color(for: .credentialMissing) == .secondary)
        #expect(AccountStatusBadge.color(for: .signedIn) == .secondary)
        #expect(AccountStatusBadge.color(for: .checking) == .secondary)
    }
}
