//
//  LocalNamespaceImportTests.swift
//  YatteeTests
//
//  Importing the signed-out account namespace into the Apple account that
//  claims it.
//

import Testing
import Foundation
@testable import Yattee

@Suite("Local namespace import")
@MainActor
struct LocalNamespaceImportTests {
    private var localScope: String { CredentialIdentityScope.localScope }

    // MARK: - Basics

    @Test("An account created while signed out follows the identity that signs in")
    func accountCredentialAndContextAreImported() async throws {
        let harness = Harness(startingScope: CredentialIdentityScope.localScope)
        let instance = harness.addInstance()

        let account = harness.accounts.addAccount(instanceID: instance.id, displayName: "Main")
        harness.credentials.setCredential("secret", for: account)
        harness.credentials.setUsername("btest1", for: account)
        harness.accounts.setContext(.account(account.id))
        defer { harness.cleanUp(account.id) }

        try await harness.flip(to: "identity-A")

        // The record landed in the identity's namespace, owed to the server.
        #expect(harness.accounts.account(id: account.id)?.displayName == "Main")
        #expect(harness.accounts.pendingUploads.contains(account.id))

        // The credential came with it and reads under the new scope.
        #expect(harness.credentials.credential(for: account) == "secret")
        #expect(harness.credentials.username(for: account) == "btest1")
        #expect(harness.credentials.isLoggedIn(for: account))

        // Move semantics: nothing is left behind in either store.
        #expect(harness.rawCredential(scope: localScope, accountID: account.id) == nil)
        #expect(harness.rawUsername(scope: localScope, accountID: account.id) == nil)
        #expect(harness.storedAccounts(in: localScope).isEmpty)

        // The selection carried over, epoch-stamped and owed to the server.
        #expect(harness.accounts.currentContext == .account(account.id))
        #expect(harness.accounts.storedContext.isMigrated)
        #expect(harness.accounts.pendingContextUpload)

        // Its instance's migration marker travelled with it.
        #expect(harness.accounts.migratedInstanceIDs.contains(instance.id))
    }

    @Test("An account that was never signed in imports and prunes cleanly")
    func accountWithoutCredentialImports() async throws {
        let harness = Harness(startingScope: CredentialIdentityScope.localScope)
        let account = harness.accounts.addAccount(instanceID: UUID(), displayName: "Never signed in")
        defer { harness.cleanUp(account.id) }

        try await harness.flip(to: "identity-A")

        #expect(harness.accounts.account(id: account.id)?.displayName == "Never signed in")
        #expect(harness.credentials.credential(for: account) == nil)
        #expect(harness.storedAccounts(in: localScope).isEmpty)
    }

    // MARK: - Collisions

    @Test("An account the identity already holds keeps its record and only fills gaps")
    func collisionKeepsTheIdentityRecord() async throws {
        let harness = Harness(startingScope: CredentialIdentityScope.localScope)
        let instanceID = UUID()

        let newer = UUID()
        let older = UUID()
        let alreadySignedIn = UUID()
        defer { harness.cleanUp(newer, older, alreadySignedIn) }

        // What the identity already knows, from its own devices.
        harness.seed("identity-A") { manager in
            for id in [newer, older, alreadySignedIn] {
                manager.applySyncedAccount(
                    Account(
                        id: id,
                        instanceID: instanceID,
                        displayName: "Identity",
                        updatedAt: Date(timeIntervalSince1970: 1000)
                    )
                )
            }
        }
        harness.seedCredential("identity-secret", accountID: alreadySignedIn, scope: "identity-A")

        // What the device holds from being signed out.
        harness.accounts.applySyncedAccount(
            Account(id: newer, instanceID: instanceID, displayName: "Local newer", updatedAt: Date())
        )
        harness.accounts.applySyncedAccount(
            Account(
                id: older,
                instanceID: instanceID,
                displayName: "Local older",
                updatedAt: Date(timeIntervalSince1970: 500)
            )
        )
        harness.accounts.applySyncedAccount(
            Account(
                id: alreadySignedIn,
                instanceID: instanceID,
                displayName: "Identity",
                updatedAt: Date(timeIntervalSince1970: 1000)
            )
        )
        harness.seedCredential("local-secret", accountID: newer, scope: localScope)
        harness.seedCredential("local-secret", accountID: alreadySignedIn, scope: localScope)

        try await harness.flip(to: "identity-A")

        // A strictly newer label is merged; an older one is not.
        #expect(harness.accounts.account(id: newer)?.displayName == "Local newer")
        #expect(harness.accounts.account(id: older)?.displayName == "Identity")

        // A credential is only ever filled in where the identity had none.
        #expect(harness.rawCredential(scope: "identity-A", accountID: newer) == "local-secret")
        #expect(harness.rawCredential(scope: "identity-A", accountID: alreadySignedIn) == "identity-secret")

        // The redundant copies are gone and the local namespace is empty.
        #expect(harness.rawCredential(scope: localScope, accountID: newer) == nil)
        #expect(harness.rawCredential(scope: localScope, accountID: alreadySignedIn) == nil)
        #expect(harness.storedAccounts(in: localScope).isEmpty)
    }

    @Test("An account this identity deleted is never resurrected from a local copy")
    func tombstoneRefusesTheImport() async throws {
        let harness = Harness(startingScope: CredentialIdentityScope.localScope)
        let deleted = UUID()
        let instanceID = UUID()
        defer { harness.cleanUp(deleted) }

        harness.seed("identity-A") { $0.applyRemoteTombstone(deleted) }

        harness.accounts.applySyncedAccount(Account(id: deleted, instanceID: instanceID))
        harness.seedCredential("local-secret", accountID: deleted, scope: localScope)
        let survivor = harness.accounts.addAccount(instanceID: UUID())
        defer { harness.cleanUp(survivor.id) }

        try await harness.flip(to: "identity-A")

        #expect(harness.accounts.account(id: deleted) == nil)
        // Nothing is owed to the server for a record that was refused — and the
        // account that *was* imported still is.
        #expect(harness.accounts.pendingUploads == [survivor.id])
        #expect(harness.accounts.pendingDeletions.isEmpty)

        // The secret went with the refused record, under both scopes.
        #expect(harness.rawCredential(scope: localScope, accountID: deleted) == nil)
        #expect(harness.rawCredential(scope: "identity-A", accountID: deleted) == nil)
        #expect(harness.storedAccounts(in: localScope).isEmpty)
    }

    // MARK: - Context

    @Test("A context chosen while signed out is dropped when the identity has one")
    func identityContextWins() async throws {
        let harness = Harness(startingScope: CredentialIdentityScope.localScope)
        let account = harness.accounts.addAccount(instanceID: UUID())
        defer { harness.cleanUp(account.id) }

        harness.accounts.setContext(.account(account.id))
        harness.seed("identity-A") { $0.setContext(.local) }

        try await harness.flip(to: "identity-A")

        #expect(harness.accounts.currentContext == .local)
        // The local keys are cleared either way, or every activation would offer
        // the same stale selection again.
        #expect(harness.defaults.data(forKey: "accounts.local.context") == nil)
        #expect(!harness.defaults.bool(forKey: "accounts.local.hasContext"))
    }

    @Test("A context naming an account the identity refused falls back to local data")
    func contextNamingARefusedAccountFallsBack() async throws {
        let harness = Harness(startingScope: CredentialIdentityScope.localScope)
        let deleted = UUID()
        defer { harness.cleanUp(deleted) }

        harness.seed("identity-A") { $0.applyRemoteTombstone(deleted) }

        harness.accounts.applySyncedAccount(Account(id: deleted, instanceID: UUID()))
        harness.accounts.setContext(.account(deleted))

        try await harness.flip(to: "identity-A")

        #expect(harness.accounts.account(id: deleted) == nil)
        #expect(harness.accounts.currentContext == .local)
        #expect(harness.accounts.storedContext.isMigrated)
    }

    // MARK: - Repetition

    @Test("Sweeping again changes nothing and duplicates nothing")
    func sweepIsIdempotent() async throws {
        let harness = Harness(startingScope: CredentialIdentityScope.localScope)
        let account = harness.accounts.addAccount(instanceID: UUID(), displayName: "Main")
        harness.credentials.setCredential("secret", for: account)
        harness.accounts.setContext(.account(account.id))
        defer { harness.cleanUp(account.id) }

        try await harness.flip(to: "identity-A")

        let accountsAfterFirst = harness.accounts.accounts
        let uploadsAfterFirst = harness.accounts.pendingUploads
        let contextAfterFirst = harness.accounts.storedContext

        #expect(harness.importer.sweepIfNeeded() == false)
        #expect(harness.importer.sweepIfNeeded() == false)

        #expect(harness.accounts.accounts == accountsAfterFirst)
        #expect(harness.accounts.pendingUploads == uploadsAfterFirst)
        #expect(harness.accounts.storedContext == contextAfterFirst)
        #expect(harness.credentials.credential(for: account) == "secret")
    }

    @Test("A sign-out and sign-in cycle imports only what is new")
    func repeatedCyclesImportOnlyTheNewAccounts() async throws {
        let harness = Harness(startingScope: CredentialIdentityScope.localScope)
        let first = harness.accounts.addAccount(instanceID: UUID(), displayName: "First")
        harness.credentials.setCredential("first-secret", for: first)
        defer { harness.cleanUp(first.id) }

        try await harness.flip(to: "identity-A")
        #expect(harness.accounts.accounts.map(\.id) == [first.id])

        // Signed out again: the local namespace is empty, and whatever is added
        // now lands there.
        try await harness.flip(to: CredentialIdentityScope.localScope)
        #expect(harness.accounts.accounts.isEmpty)

        let second = harness.accounts.addAccount(instanceID: UUID(), displayName: "Second")
        harness.credentials.setCredential("second-secret", for: second)
        defer { harness.cleanUp(second.id) }

        try await harness.flip(to: "identity-A")

        #expect(harness.accounts.accounts.count == 2)
        #expect(harness.accounts.account(id: first.id)?.displayName == "First")
        #expect(harness.accounts.account(id: second.id)?.displayName == "Second")
        #expect(harness.credentials.credential(for: first) == "first-secret")
        #expect(harness.credentials.credential(for: second) == "second-secret")
        #expect(harness.storedAccounts(in: localScope).isEmpty)
    }

    @Test("The signed-out migration markers stay behind, so nothing is synthesized twice")
    func localMigrationMarkersAreRetained() async throws {
        let harness = Harness(startingScope: CredentialIdentityScope.localScope)
        let instance = harness.addInstance(usesAccountLogin: true)
        defer { harness.cleanUp(instance.id) }

        harness.accounts.reconcileLegacyAccounts()
        let synthesized = try #require(harness.accounts.accounts(forInstance: instance.id).first)
        #expect(synthesized.id == instance.id)

        try await harness.flip(to: "identity-A")
        #expect(harness.accounts.account(id: instance.id) != nil)
        #expect(harness.accounts.migratedInstanceIDs.contains(instance.id))

        // Signing out again must not re-synthesize the account that just left:
        // `usesAccountLogin` is still true on the instance forever, and only the
        // retained marker stops the migration running a second time.
        try await harness.flip(to: CredentialIdentityScope.localScope)
        #expect(harness.accounts.accounts.isEmpty)

        harness.accounts.reconcileLegacyAccounts()
        #expect(harness.accounts.accounts.isEmpty)
        #expect(harness.accounts.migratedInstanceIDs.contains(instance.id))
    }

    @Test("A deletion made while signed out is never published into the Apple account")
    func localDeletionFactsStayLocal() async throws {
        let harness = Harness(startingScope: CredentialIdentityScope.localScope)
        let doomed = harness.accounts.addAccount(instanceID: UUID())
        harness.accounts.removeAccount(doomed.id)

        let kept = harness.accounts.addAccount(instanceID: UUID())
        defer { harness.cleanUp(doomed.id, kept.id) }

        try await harness.flip(to: "identity-A")

        #expect(harness.accounts.accounts.map(\.id) == [kept.id])
        #expect(harness.accounts.deletedAccountIDs.isEmpty)
        #expect(harness.accounts.pendingDeletions.isEmpty)
        // ...and the local namespace keeps them, so signing out still works.
        #expect(
            harness.defaults.array(forKey: "accounts.local.deletedAccounts") as? [String]
                == [doomed.id.uuidString]
        )
    }

    // MARK: - Fences

    @Test("A sweep is refused while the account namespace is still reloading")
    func sweepIsFencedOnTheLoadedNamespace() {
        let harness = Harness(startingScope: CredentialIdentityScope.localScope)
        let account = harness.accounts.addAccount(instanceID: UUID())
        harness.credentials.setCredential("secret", for: account)
        defer { harness.cleanUp(account.id) }

        // The scope moves before the observer that reloads the manager runs.
        harness.scope.setFixedScope("identity-A", announcing: false)

        #expect(harness.importer.sweepIfNeeded() == false)
        #expect(harness.storedAccounts(in: localScope).map(\.id) == [account.id])
        #expect(harness.defaults.data(forKey: "accounts.identity-A.accounts") == nil)
        #expect(harness.rawCredential(scope: localScope, accountID: account.id) == "secret")
    }

    @Test("An unresolved scope is never a destination, and the identity sweeps once")
    func unresolvedScopeIsNotADestination() async throws {
        let harness = Harness(startingScope: CredentialIdentityScope.localScope)
        let account = harness.accounts.addAccount(instanceID: UUID(), displayName: "Main")
        harness.credentials.setCredential("secret", for: account)
        defer { harness.cleanUp(account.id) }

        // iCloud is signed in but the user record has not been fetched yet.
        try await harness.flip(to: nil)
        #expect(harness.sweeps == 0)
        #expect(harness.storedAccounts(in: localScope).map(\.id) == [account.id])
        #expect(harness.defaults.data(forKey: "accounts.unresolved.accounts") == nil)

        try await harness.flip(to: "identity-A")
        #expect(harness.sweeps == 1)
        #expect(harness.accounts.account(id: account.id) != nil)

        // Any later activation of the same identity finds nothing left to do.
        harness.accounts.reloadForCurrentIdentity()
        #expect(harness.sweeps == 1)
        #expect(harness.accounts.account(id: account.id) != nil)
    }

    @Test("Whichever identity activates claims what was made while signed out")
    func identitySwitchClaimsTheLocalNamespace() async throws {
        let harness = Harness(startingScope: "identity-A")
        let held = harness.accounts.addAccount(instanceID: UUID(), displayName: "A's own")
        defer { harness.cleanUp(held.id) }

        // Made while the device was signed out, before B signed in.
        let madeSignedOut = UUID()
        defer { harness.cleanUp(madeSignedOut) }
        harness.seed(CredentialIdentityScope.localScope) { manager in
            manager.applySyncedAccount(
                Account(id: madeSignedOut, instanceID: UUID(), displayName: "Made signed out")
            )
        }
        harness.seedCredential("local-secret", accountID: madeSignedOut, scope: localScope)

        try await harness.flip(to: "identity-B")

        #expect(harness.accounts.account(id: madeSignedOut)?.displayName == "Made signed out")
        #expect(harness.accounts.pendingUploads.contains(madeSignedOut))
        #expect(harness.rawCredential(scope: "identity-B", accountID: madeSignedOut) == "local-secret")
        #expect(harness.storedAccounts(in: localScope).isEmpty)

        // A's own namespace is untouched by B claiming the local one.
        #expect(harness.storedAccounts(in: "identity-A").map(\.id) == [held.id])
        #expect(harness.accounts.account(id: held.id) == nil)
    }
}

// MARK: - Test Support

/// A full local-namespace setup: storage, a Keychain service, an identity scope
/// that can be moved, and the importer wired the way the app wires it.
@MainActor
private final class Harness {
    let defaults: UserDefaults
    let scope: CredentialIdentityScope
    let instances: InstancesManager
    let accounts: AccountsManager
    let credentials: TestCredentialsManager
    let importer: LocalNamespaceImporter

    /// Sweeps that actually took something over.
    private(set) var sweeps = 0

    private let store: KeychainCredentialStore

    init(startingScope: String?) {
        let defaults = UserDefaults(suiteName: "yattee.tests.\(UUID().uuidString)")!
        // Unique per run so a crashed run's leftovers can never be read back.
        let service = "com.yattee.tests.\(UUID().uuidString)"

        self.defaults = defaults
        self.store = KeychainCredentialStore(service: service)
        self.instances = makeTestInstancesManager()

        let scope = CredentialIdentityScope(fixedScope: startingScope)
        self.scope = scope

        let accounts = AccountsManager(
            identityScope: scope,
            instancesManager: instances,
            defaults: defaults
        )
        self.accounts = accounts

        let credentials = TestCredentialsManager(
            service: service,
            identityScope: scope,
            markers: CredentialAdoptionMarkerStore(defaults: defaults)
        )
        self.credentials = credentials

        self.importer = LocalNamespaceImporter(
            accountsManager: accounts,
            identityScope: scope,
            credentialStores: { _ in [credentials] }
        )

        accounts.onNamespaceActivated = { [weak self] in
            guard let self, self.importer.sweepIfNeeded() else { return }
            self.sweeps += 1
        }
    }

    // MARK: Driving

    /// Moves the identity scope the way a sign-in does, and lets the main-queue
    /// observers that reload and sweep run.
    func flip(to newScope: String?) async throws {
        scope.setFixedScope(newScope)
        try await Task.sleep(for: .milliseconds(50))
    }

    @discardableResult
    func addInstance(usesAccountLogin: Bool = false) -> Instance {
        let instance = Instance(
            type: .invidious,
            url: URL(string: "https://import-\(UUID().uuidString).example.com")!,
            usesAccountLogin: usesAccountLogin
        )
        instances.add(instance)
        return instance
    }

    /// Writes into a namespace other than the one under test, the way another
    /// device's sync would have filled it.
    func seed(_ namespace: String, _ body: (AccountsManager) -> Void) {
        body(
            AccountsManager(
                identityScope: CredentialIdentityScope(fixedScope: namespace),
                instancesManager: instances,
                defaults: defaults
            )
        )
    }

    func seedCredential(_ value: String, accountID: UUID, scope: String) {
        store.set(
            value,
            forKey: KeychainCredentialStore.credentialKey(scope: scope, accountID: accountID),
            synchronizable: false
        )
    }

    // MARK: Reading storage directly

    func storedAccounts(in namespace: String) -> [Account] {
        guard let data = defaults.data(forKey: "accounts.\(namespace).accounts"),
              let decoded = try? JSONDecoder().decode([Account].self, from: data)
        else { return [] }
        return decoded
    }

    func rawCredential(scope: String, accountID: UUID) -> String? {
        store.value(forKey: KeychainCredentialStore.credentialKey(scope: scope, accountID: accountID))
    }

    func rawUsername(scope: String, accountID: UUID) -> String? {
        store.value(forKey: KeychainCredentialStore.usernameKey(scope: scope, accountID: accountID))
    }

    /// The Keychain outlives the test process, so every key a test could have
    /// written is removed by hand.
    func cleanUp(_ accountIDs: UUID...) {
        for accountID in accountIDs {
            for scope in [CredentialIdentityScope.localScope, "identity-A", "identity-B", "unresolved"] {
                store.delete(key: KeychainCredentialStore.credentialKey(scope: scope, accountID: accountID))
                store.delete(key: KeychainCredentialStore.usernameKey(scope: scope, accountID: accountID))
            }
            store.delete(key: KeychainCredentialStore.legacyKey(instanceID: accountID))
        }
    }
}

/// An account-keyed credential store over a Keychain service of its own.
///
/// The shipping managers hard-code their service names, which under a test host
/// are the ones the installed app uses. This wraps the same engine they wrap, so
/// the protocol the importer talks to is exercised for real.
@MainActor
@Observable
private final class TestCredentialsManager: AccountCredentialsManager {
    private let credentials: AccountKeychainCredentials

    init(service: String, identityScope: CredentialIdentityScope, markers: CredentialAdoptionMarkerStore) {
        credentials = AccountKeychainCredentials(
            service: service,
            credentialNoun: "credential",
            identityScope: identityScope,
            markers: markers
        )
    }

    var loggedInAccountIDs: Set<UUID> { credentials.loggedInAccountIDs }
    var isScopeResolved: Bool { credentials.isScopeResolved }

    func setCredential(_ credential: String, for account: Account) {
        credentials.setCredential(credential, for: account)
    }

    func credential(for account: Account) -> String? { credentials.credential(for: account) }

    func deleteCredential(for account: Account) { credentials.deleteCredential(for: account) }

    func deleteCredential(forAccountID accountID: UUID) {
        credentials.deleteCredential(forAccountID: accountID)
    }

    func resyncCredentialsWithCurrentSetting() { credentials.resyncCredentialsWithCurrentSetting() }

    func setUsername(_ username: String, for account: Account) {
        credentials.setUsername(username, for: account)
    }

    func username(for account: Account) -> String? { credentials.username(for: account) }

    func isLoggedIn(for account: Account) -> Bool { credentials.isLoggedIn(for: account) }

    func refreshLoginStatus(for account: Account) { credentials.refreshLoginStatus(for: account) }

    @discardableResult
    func migrateCredential(forAccountID accountID: UUID, fromScope sourceScope: String) -> Bool {
        credentials.migrateCredential(forAccountID: accountID, fromScope: sourceScope)
    }

    func deleteCredential(forAccountID accountID: UUID, inScope scope: String) {
        credentials.deleteCredential(forAccountID: accountID, inScope: scope)
    }

    func hasAdoptableLegacyCredential(for account: Account) -> Bool {
        credentials.hasAdoptableLegacyCredential(for: account)
    }

    @discardableResult
    func adoptLegacyCredential(for account: Account) -> Bool {
        credentials.adoptLegacyCredential(for: account)
    }

    func deleteLegacyCredentialIfOwned(for account: Account) {
        credentials.deleteLegacyCredentialIfOwned(for: account)
    }
}
