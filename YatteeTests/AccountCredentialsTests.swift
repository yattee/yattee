//
//  AccountCredentialsTests.swift
//  YatteeTests
//
//  Identity-scoped, account-keyed credential storage and legacy adoption.
//

import Testing
import Foundation
@testable import Yattee

@Suite("Account credential scoping")
@MainActor
struct AccountCredentialScopingTests {
    /// A service name unique per test run so parallel runs and leftovers from a
    /// crashed run can never collide in the real Keychain.
    private func makeService() -> String {
        "com.yattee.tests.\(UUID().uuidString)"
    }

    private func makeCredentials(
        service: String,
        scope: String?,
        markers: CredentialAdoptionMarkerStore
    ) -> AccountKeychainCredentials {
        AccountKeychainCredentials(
            service: service,
            credentialNoun: "credential",
            identityScope: CredentialIdentityScope(fixedScope: scope),
            markers: markers
        )
    }

    private func makeMarkers() -> CredentialAdoptionMarkerStore {
        CredentialAdoptionMarkerStore(
            defaults: UserDefaults(suiteName: "yattee.tests.\(UUID().uuidString)")!
        )
    }

    @Test("Credential key carries the identity scope")
    func credentialKeyIsScoped() {
        let accountID = UUID()
        let key = KeychainCredentialStore.credentialKey(scope: "identity-A", accountID: accountID)

        #expect(key == "identity-A|\(accountID.uuidString)")
        #expect(
            KeychainCredentialStore.usernameKey(scope: "identity-A", accountID: accountID)
                == "identity-A|\(accountID.uuidString)#username"
        )
        // The legacy key must stay a bare UUID, or existing items stop resolving.
        #expect(KeychainCredentialStore.legacyKey(instanceID: accountID) == accountID.uuidString)
    }

    @Test("A credential stored under one Apple account is invisible to another")
    func credentialsAreIsolatedAcrossIdentities() {
        let service = makeService()
        let markers = makeMarkers()
        let account = Account(instanceID: UUID())

        let identityA = makeCredentials(service: service, scope: "identity-A", markers: markers)
        identityA.setCredential("secret-a", for: account)
        #expect(identityA.credential(for: account) == "secret-a")

        // Same device, same deterministic account UUID, different Apple account.
        let identityB = makeCredentials(service: service, scope: "identity-B", markers: markers)
        #expect(identityB.credential(for: account) == nil)
        #expect(identityB.isLoggedIn(for: account) == false)

        // A's credential is untouched when A comes back.
        let identityAAgain = makeCredentials(service: service, scope: "identity-A", markers: markers)
        #expect(identityAAgain.credential(for: account) == "secret-a")

        identityAAgain.deleteCredential(for: account)
    }

    @Test("Usernames are scoped exactly like credentials")
    func usernamesAreScoped() {
        let service = makeService()
        let markers = makeMarkers()
        let account = Account(instanceID: UUID())

        let identityA = makeCredentials(service: service, scope: "identity-A", markers: markers)
        identityA.setUsername("someone@example.com", for: account)
        #expect(identityA.username(for: account) == "someone@example.com")

        let identityB = makeCredentials(service: service, scope: "identity-B", markers: markers)
        #expect(identityB.username(for: account) == nil)

        identityA.deleteCredential(for: account)
        #expect(identityA.username(for: account) == nil)
    }

    @Test("An unresolved scope refuses writes and reports nothing signed in")
    func unresolvedScopeRefusesAccess() {
        let service = makeService()
        let account = Account(instanceID: UUID())

        let credentials = makeCredentials(service: service, scope: nil, markers: makeMarkers())
        #expect(credentials.isScopeResolved == false)

        credentials.setCredential("should-not-persist", for: account)

        // Nothing was written under a guessed scope, so nothing can be read back
        // once the real scope arrives.
        let resolved = makeCredentials(service: service, scope: "identity-A", markers: makeMarkers())
        #expect(resolved.credential(for: account) == nil)
    }

    @Test("Switching identity drops the cached login set")
    func identitySwitchClearsLoginCache() {
        let service = makeService()
        let markers = makeMarkers()
        let account = Account(instanceID: UUID())
        let scope = CredentialIdentityScope(fixedScope: "identity-A")

        let credentials = AccountKeychainCredentials(
            service: service,
            credentialNoun: "credential",
            identityScope: scope,
            markers: markers
        )
        credentials.setCredential("secret-a", for: account)
        #expect(credentials.loggedInAccountIDs.contains(account.id))

        scope.adoptCurrentIdentity() // real device identity — no longer "identity-A"
        #expect(credentials.isLoggedIn(for: account) == false)
        #expect(!credentials.loggedInAccountIDs.contains(account.id))

        let cleanup = makeCredentials(service: service, scope: "identity-A", markers: markers)
        cleanup.deleteCredential(for: account)
    }
}

@Suite("Legacy credential adoption")
@MainActor
struct LegacyCredentialAdoptionTests {
    private func makeService() -> String {
        "com.yattee.tests.\(UUID().uuidString)"
    }

    private func makeMarkers() -> CredentialAdoptionMarkerStore {
        CredentialAdoptionMarkerStore(
            defaults: UserDefaults(suiteName: "yattee.tests.\(UUID().uuidString)")!
        )
    }

    /// Writes the pre-revamp item: unscoped, keyed by bare instance UUID.
    private func seedLegacyItem(service: String, instanceID: UUID, value: String) {
        let store = KeychainCredentialStore(service: service)
        store.set(value, forKey: KeychainCredentialStore.legacyKey(instanceID: instanceID), synchronizable: false)
    }

    private func legacyValue(service: String, instanceID: UUID) -> String? {
        KeychainCredentialStore(service: service)
            .value(forKey: KeychainCredentialStore.legacyKey(instanceID: instanceID))
    }

    private func makeCredentials(
        service: String,
        scope: String,
        markers: CredentialAdoptionMarkerStore
    ) -> AccountKeychainCredentials {
        AccountKeychainCredentials(
            service: service,
            credentialNoun: "credential",
            identityScope: CredentialIdentityScope(fixedScope: scope),
            markers: markers
        )
    }

    @Test("A legacy credential is never adopted automatically")
    func legacyCredentialIsNotAutoAdopted() {
        let service = makeService()
        let instanceID = UUID()
        let account = Account.migrated(from: instanceID)
        seedLegacyItem(service: service, instanceID: instanceID, value: "legacy-secret")

        let credentials = makeCredentials(service: service, scope: "identity-B", markers: makeMarkers())

        // Reading never falls back to the unscoped item — that is the whole
        // point of scoping, since a retained item proves nothing about who owns it.
        #expect(credentials.credential(for: account) == nil)
        #expect(credentials.isLoggedIn(for: account) == false)
        // But it is offered as an explicit action.
        #expect(credentials.hasAdoptableLegacyCredential(for: account) == true)

        KeychainCredentialStore(service: service)
            .delete(key: KeychainCredentialStore.legacyKey(instanceID: instanceID))
    }

    @Test("Adoption copies the legacy item and retains it")
    func adoptionCopiesAndRetains() {
        let service = makeService()
        let instanceID = UUID()
        let account = Account.migrated(from: instanceID)
        seedLegacyItem(service: service, instanceID: instanceID, value: "legacy-secret")

        let credentials = makeCredentials(service: service, scope: "identity-A", markers: makeMarkers())
        #expect(credentials.adoptLegacyCredential(for: account) == true)

        #expect(credentials.credential(for: account) == "legacy-secret")
        // Retained: deleting it would propagate through iCloud Keychain and log
        // out devices still running the previous release.
        #expect(legacyValue(service: service, instanceID: instanceID) == "legacy-secret")
        // Adopted once, never offered again for this identity.
        #expect(credentials.hasAdoptableLegacyCredential(for: account) == false)

        credentials.deleteCredential(for: account)
        KeychainCredentialStore(service: service)
            .delete(key: KeychainCredentialStore.legacyKey(instanceID: instanceID))
    }

    @Test("Adoption by one identity does not suppress the offer for another")
    func adoptionIsPerIdentity() {
        let service = makeService()
        let markers = makeMarkers()
        let instanceID = UUID()
        let account = Account.migrated(from: instanceID)
        seedLegacyItem(service: service, instanceID: instanceID, value: "legacy-secret")

        let identityA = makeCredentials(service: service, scope: "identity-A", markers: markers)
        #expect(identityA.adoptLegacyCredential(for: account) == true)

        let identityB = makeCredentials(service: service, scope: "identity-B", markers: markers)
        #expect(identityB.credential(for: account) == nil)
        #expect(identityB.hasAdoptableLegacyCredential(for: account) == true)

        identityA.deleteCredential(for: account)
        KeychainCredentialStore(service: service)
            .delete(key: KeychainCredentialStore.legacyKey(instanceID: instanceID))
    }

    @Test("Deleting an account removes the legacy item only for the adopting identity")
    func legacyDeletionRequiresIdentityMatch() {
        let service = makeService()
        let markers = makeMarkers()
        let instanceID = UUID()
        let account = Account.migrated(from: instanceID)
        seedLegacyItem(service: service, instanceID: instanceID, value: "legacy-secret")

        let identityA = makeCredentials(service: service, scope: "identity-A", markers: markers)
        #expect(identityA.adoptLegacyCredential(for: account) == true)

        // B never adopted anything, so B may not delete the shared legacy item.
        let identityB = makeCredentials(service: service, scope: "identity-B", markers: markers)
        identityB.deleteLegacyCredentialIfOwned(for: account)
        #expect(legacyValue(service: service, instanceID: instanceID) == "legacy-secret")

        // A adopted it and it still holds the adopted secret, so A may.
        identityA.deleteLegacyCredentialIfOwned(for: account)
        #expect(legacyValue(service: service, instanceID: instanceID) == nil)

        identityA.deleteCredential(for: account)
    }

    @Test("Deleting a sibling account leaves the adopter's legacy item alone")
    func legacyDeletionRequiresAccountMatch() {
        let service = makeService()
        let markers = makeMarkers()
        let instanceID = UUID()
        let adopter = Account.migrated(from: instanceID)
        // A second login on the same instance — a fresh UUID, not the migrated one.
        let sibling = Account(instanceID: instanceID)
        seedLegacyItem(service: service, instanceID: instanceID, value: "legacy-secret")

        let credentials = makeCredentials(service: service, scope: "identity-A", markers: markers)
        #expect(credentials.adoptLegacyCredential(for: adopter) == true)

        // Removing the sibling must not retire the secret the migrated account
        // adopted — old-release devices are still using it.
        credentials.deleteLegacyCredentialIfOwned(for: sibling)
        #expect(legacyValue(service: service, instanceID: instanceID) == "legacy-secret")

        credentials.deleteLegacyCredentialIfOwned(for: adopter)
        #expect(legacyValue(service: service, instanceID: instanceID) == nil)

        credentials.deleteCredential(for: adopter)
    }

    @Test("Adoption does not overwrite a scoped credential that arrived first")
    func adoptionDoesNotClobberArrivedCredential() {
        let service = makeService()
        let instanceID = UUID()
        let account = Account.migrated(from: instanceID)
        seedLegacyItem(service: service, instanceID: instanceID, value: "legacy-secret")

        let credentials = makeCredentials(service: service, scope: "identity-A", markers: makeMarkers())
        // iCloud Keychain delivers the real credential between the offer being
        // rendered and the user tapping it.
        credentials.setCredential("synced-secret", for: account)

        #expect(credentials.hasAdoptableLegacyCredential(for: account) == false)
        #expect(credentials.adoptLegacyCredential(for: account) == false)
        #expect(credentials.credential(for: account) == "synced-secret")

        credentials.deleteCredential(for: account)
        KeychainCredentialStore(service: service)
            .delete(key: KeychainCredentialStore.legacyKey(instanceID: instanceID))
    }

    @Test("A legacy item replaced by another login survives the adopter's deletion")
    func legacyDeletionRequiresFingerprintMatch() {
        let service = makeService()
        let markers = makeMarkers()
        let instanceID = UUID()
        let account = Account.migrated(from: instanceID)
        seedLegacyItem(service: service, instanceID: instanceID, value: "legacy-secret")

        let identityA = makeCredentials(service: service, scope: "identity-A", markers: markers)
        #expect(identityA.adoptLegacyCredential(for: account) == true)

        // Someone else signed in on an older release, which rewrote the
        // unscoped key. That login is live on their devices.
        seedLegacyItem(service: service, instanceID: instanceID, value: "someone-elses-secret")

        identityA.deleteLegacyCredentialIfOwned(for: account)
        #expect(legacyValue(service: service, instanceID: instanceID) == "someone-elses-secret")

        identityA.deleteCredential(for: account)
        KeychainCredentialStore(service: service)
            .delete(key: KeychainCredentialStore.legacyKey(instanceID: instanceID))
    }

    @Test("Adoption is refused while the identity scope is unresolved")
    func adoptionRefusedWhenUnresolved() {
        let service = makeService()
        let instanceID = UUID()
        let account = Account.migrated(from: instanceID)
        seedLegacyItem(service: service, instanceID: instanceID, value: "legacy-secret")

        let credentials = AccountKeychainCredentials(
            service: service,
            credentialNoun: "credential",
            identityScope: CredentialIdentityScope(fixedScope: nil),
            markers: makeMarkers()
        )

        #expect(credentials.hasAdoptableLegacyCredential(for: account) == false)
        #expect(credentials.adoptLegacyCredential(for: account) == false)

        KeychainCredentialStore(service: service)
            .delete(key: KeychainCredentialStore.legacyKey(instanceID: instanceID))
    }
}

@Suite("Credential identity scope resolution")
@MainActor
struct CredentialIdentityScopeTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "yattee.tests.\(UUID().uuidString)")!
    }

    /// Mutable identity + resolver so a switch can be staged mid-resolution.
    private final class Harness: @unchecked Sendable {
        var fingerprint: String? = "identity-A"
        var resultsByFingerprint: [String: String] = [:]
        var failuresRemaining = 0
        var onResolveStart: (() -> Void)?
        var switchTask: Task<Void, Never>?

        func resolve() async -> String? {
            onResolveStart?()
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                return nil
            }
            guard let fingerprint else { return nil }
            return resultsByFingerprint[fingerprint]
        }
    }

    @Test("A transient failure is retried rather than disabling credentials forever")
    func transientFailureIsRetried() async {
        let harness = Harness()
        harness.resultsByFingerprint = ["identity-A": "_recordA"]
        harness.failuresRemaining = 2

        let scope = CredentialIdentityScope(
            defaults: makeDefaults(),
            fingerprintProvider: { harness.fingerprint },
            resolveUserRecordID: { await harness.resolve() },
            retryDelay: { _ in }
        )

        #expect(scope.isResolved == false)
        await scope.resolve()
        #expect(scope.current == "_recordA")
    }

    @Test("Exhausted attempts are retried on foreground activation")
    func exhaustedAttemptsRetryOnForeground() async {
        let harness = Harness()
        harness.resultsByFingerprint = ["identity-A": "_recordA"]
        harness.failuresRemaining = 99 // every attempt fails

        let scope = CredentialIdentityScope(
            defaults: makeDefaults(),
            fingerprintProvider: { harness.fingerprint },
            resolveUserRecordID: { await harness.resolve() },
            retryDelay: { _ in }
        )

        await scope.resolve()
        #expect(scope.isResolved == false)

        // Connectivity returns; the app comes back to the foreground.
        harness.failuresRemaining = 0
        await scope.resolveIfNeeded()
        #expect(scope.current == "_recordA")
    }

    @Test("An identity switch mid-resolution resolves the new identity")
    func switchDuringResolutionResolvesNewIdentity() async {
        let harness = Harness()
        harness.resultsByFingerprint = ["identity-A": "_recordA", "identity-B": "_recordB"]

        let scope = CredentialIdentityScope(
            defaults: makeDefaults(),
            fingerprintProvider: { harness.fingerprint },
            resolveUserRecordID: { await harness.resolve() },
            retryDelay: { _ in }
        )

        // The Apple account switches while A's lookup is in flight — exactly
        // what the notification observer does, only deterministically.
        harness.onResolveStart = { [weak scope] in
            harness.onResolveStart = nil
            harness.fingerprint = "identity-B"
            MainActor.assumeIsolated {
                scope?.adoptCurrentIdentity()
                harness.switchTask = Task { await scope?.resolve() }
            }
        }

        await scope.resolve()
        await harness.switchTask?.value

        // A's result must be discarded, and B must not be left unresolved.
        #expect(scope.current != "_recordA")
        #expect(scope.current == "_recordB")
    }

    @Test("Signing out scopes to local without a lookup")
    func signedOutUsesLocalScope() {
        let harness = Harness()
        harness.fingerprint = nil

        let scope = CredentialIdentityScope(
            defaults: makeDefaults(),
            fingerprintProvider: { harness.fingerprint },
            resolveUserRecordID: { await harness.resolve() },
            retryDelay: { _ in }
        )

        #expect(scope.current == CredentialIdentityScope.localScope)
    }

    @Test("A known Apple account resolves synchronously on relaunch")
    func cachedScopeResolvesSynchronously() async {
        let defaults = makeDefaults()
        let harness = Harness()
        harness.resultsByFingerprint = ["identity-A": "_recordA"]

        let first = CredentialIdentityScope(
            defaults: defaults,
            fingerprintProvider: { harness.fingerprint },
            resolveUserRecordID: { await harness.resolve() },
            retryDelay: { _ in }
        )
        await first.resolve()
        #expect(first.current == "_recordA")

        // Relaunch: no network involved this time.
        let second = CredentialIdentityScope(
            defaults: defaults,
            fingerprintProvider: { harness.fingerprint },
            resolveUserRecordID: { nil },
            retryDelay: { _ in }
        )
        #expect(second.current == "_recordA")
    }
}

@Suite("Migrated account identity")
@MainActor
struct MigratedAccountTests {
    @Test("A migrated account reuses the instance UUID")
    func migratedAccountReusesInstanceID() {
        let instanceID = UUID()
        let account = Account.migrated(from: instanceID)

        // Determinism across devices: two devices migrating the same instance
        // independently produce the identical record name, which merges
        // per-record instead of duplicating.
        #expect(account.id == instanceID)
        #expect(account.instanceID == instanceID)
        #expect(account.isMigrated)
        #expect(Account.migrated(from: instanceID).id == account.id)
    }

    @Test("A migrated account carries an epoch-old updatedAt")
    func migratedAccountLosesConflicts() {
        let migrated = Account.migrated(from: UUID())
        let explicit = Account(instanceID: UUID())

        // Any explicit user edit on any device must outrank a migration write,
        // regardless of arrival order.
        #expect(migrated.updatedAt < explicit.updatedAt)
    }

    @Test("A new account gets a fresh UUID")
    func newAccountsAreDistinct() {
        let instanceID = UUID()
        let first = Account(instanceID: instanceID)
        let second = Account(instanceID: instanceID)

        #expect(first.id != second.id)
        #expect(!first.isMigrated)
    }
}
