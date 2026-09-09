//
//  AccountCredentialsTests.swift
//  YatteeTests
//
//  Identity-scoped, account-keyed credential storage and legacy adoption.
//

import Testing
import Foundation
import Security
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
        markers: CredentialAdoptionMarkerStore,
        settingsManager: SettingsManager? = nil
    ) -> AccountKeychainCredentials {
        let credentials = AccountKeychainCredentials(
            service: service,
            credentialNoun: "credential",
            identityScope: CredentialIdentityScope(fixedScope: scope),
            markers: markers
        )
        credentials.settingsManager = settingsManager
        return credentials
    }

    @Test("Reading a credential never falls back to the unscoped legacy item")
    func readingNeverFallsBackToLegacyItem() {
        let service = makeService()
        let instanceID = UUID()
        let account = Account.migrated(from: instanceID)
        seedLegacyItem(service: service, instanceID: instanceID, value: "legacy-secret")

        let credentials = makeCredentials(service: service, scope: "identity-B", markers: makeMarkers())

        // The whole point of scoping: the legacy item is reachable only through
        // the adoption path, which copies it deliberately and records what it
        // took. An implicit read-through would leave nothing to bound deletion
        // with later.
        #expect(credentials.credential(for: account) == nil)
        #expect(credentials.isLoggedIn(for: account) == false)
        #expect(credentials.hasAdoptableLegacyCredential(for: account) == true)

        KeychainCredentialStore(service: service)
            .delete(key: KeychainCredentialStore.legacyKey(instanceID: instanceID))
    }

    @Test("An adopted credential is kept on this device even when sync is on")
    func adoptedCredentialIsNeverSynchronizable() {
        let service = makeService()
        let instanceID = UUID()
        let account = Account.migrated(from: instanceID)
        seedLegacyItem(service: service, instanceID: instanceID, value: "legacy-secret")

        let settings = SettingsManager()
        let previousSync = settings.iCloudSyncEnabled
        let previousInstances = settings.syncInstances
        settings.iCloudSyncEnabled = true
        settings.syncInstances = true
        defer {
            settings.iCloudSyncEnabled = previousSync
            settings.syncInstances = previousInstances
        }

        let credentials = makeCredentials(
            service: service,
            scope: "identity-A",
            markers: makeMarkers(),
            settingsManager: settings
        )
        #expect(credentials.adoptLegacyCredential(for: account) == true)

        // A retained legacy item cannot be shown to belong to the identity
        // signed in now. Adopting it locally leaves exposure where the previous
        // release already had it; writing it synchronizably would upload
        // somebody else's secret into this identity's iCloud Keychain.
        let store = KeychainCredentialStore(service: service)
        let key = KeychainCredentialStore.credentialKey(scope: "identity-A", accountID: account.id)
        #expect(store.isSynchronizable(key: key) == false)

        credentials.deleteCredential(for: account)
        store.delete(key: KeychainCredentialStore.legacyKey(instanceID: instanceID))
    }

    @Test("Turning iCloud sync on does not upload an adopted credential")
    func resyncLeavesAdoptedCredentialsLocal() {
        let service = makeService()
        let instanceID = UUID()
        let adopted = Account.migrated(from: instanceID)
        let typedIn = Account(instanceID: instanceID)
        seedLegacyItem(service: service, instanceID: instanceID, value: "legacy-secret")

        let settings = SettingsManager()
        let previousSync = settings.iCloudSyncEnabled
        let previousInstances = settings.syncInstances
        settings.iCloudSyncEnabled = false
        settings.syncInstances = false
        defer {
            settings.iCloudSyncEnabled = previousSync
            settings.syncInstances = previousInstances
        }

        let credentials = makeCredentials(
            service: service,
            scope: "identity-A",
            markers: makeMarkers(),
            settingsManager: settings
        )
        #expect(credentials.adoptLegacyCredential(for: adopted) == true)
        credentials.setCredential("typed-in-secret", for: typedIn)

        settings.iCloudSyncEnabled = true
        settings.syncInstances = true
        credentials.resyncCredentialsWithCurrentSetting()

        let store = KeychainCredentialStore(service: service)
        // The login the user typed is theirs, and they just asked for it to
        // sync.
        #expect(
            store.isSynchronizable(
                key: KeychainCredentialStore.credentialKey(scope: "identity-A", accountID: typedIn.id)
            ) == true
        )
        // The adopted one is left alone — its provenance is unproven, and the
        // legacy item it came from already syncs for whoever really owns it.
        #expect(
            store.isSynchronizable(
                key: KeychainCredentialStore.credentialKey(scope: "identity-A", accountID: adopted.id)
            ) == false
        )

        credentials.deleteCredential(for: adopted)
        credentials.deleteCredential(for: typedIn)
        store.delete(key: KeychainCredentialStore.legacyKey(instanceID: instanceID))
    }

    @Test("An adopted credential stays local even if its marker was never written")
    func resyncRecognizesAnAdoptedCopyWithoutItsMarker() {
        let service = makeService()
        let instanceID = UUID()
        let account = Account.migrated(from: instanceID)
        seedLegacyItem(service: service, instanceID: instanceID, value: "legacy-secret")

        let settings = SettingsManager()
        let previousSync = settings.iCloudSyncEnabled
        let previousInstances = settings.syncInstances
        settings.iCloudSyncEnabled = false
        settings.syncInstances = false
        defer {
            settings.iCloudSyncEnabled = previousSync
            settings.syncInstances = previousInstances
        }

        let store = KeychainCredentialStore(service: service)
        let key = KeychainCredentialStore.credentialKey(scope: "identity-A", accountID: account.id)
        // Exactly the state left behind when the app dies between the adoption
        // copy and the marker that describes it: the scoped item exists, no
        // marker claims it, and adoption will not retry because the key is
        // occupied.
        store.set("legacy-secret", forKey: key, synchronizable: false)

        let credentials = makeCredentials(
            service: service,
            scope: "identity-A",
            markers: makeMarkers(),
            settingsManager: settings
        )
        #expect(credentials.isLoggedIn(for: account) == true)

        settings.iCloudSyncEnabled = true
        settings.syncInstances = true
        credentials.resyncCredentialsWithCurrentSetting()

        #expect(store.isSynchronizable(key: key) == false)

        credentials.deleteCredential(for: account)
        store.delete(key: KeychainCredentialStore.legacyKey(instanceID: instanceID))
    }

    @Test("Signing in again lets the new credential sync")
    func signingInAgainClearsTheAdoptionMarker() {
        let service = makeService()
        let instanceID = UUID()
        let account = Account.migrated(from: instanceID)
        seedLegacyItem(service: service, instanceID: instanceID, value: "legacy-secret")

        let settings = SettingsManager()
        let previousSync = settings.iCloudSyncEnabled
        let previousInstances = settings.syncInstances
        settings.iCloudSyncEnabled = false
        settings.syncInstances = false
        defer {
            settings.iCloudSyncEnabled = previousSync
            settings.syncInstances = previousInstances
        }

        let markers = makeMarkers()
        let credentials = makeCredentials(
            service: service,
            scope: "identity-A",
            markers: markers,
            settingsManager: settings
        )
        #expect(credentials.adoptLegacyCredential(for: account) == true)

        // The user signs in again while sync is off, so the replacement is
        // stored locally like any other credential.
        credentials.setCredential("freshly-typed-secret", for: account)
        #expect(markers.hasAdopted(service: service, instanceID: instanceID, scope: "identity-A") == false)

        // Turning sync on must now carry it to the other devices — they are
        // showing an account whose credential never arrives.
        settings.iCloudSyncEnabled = true
        settings.syncInstances = true
        credentials.resyncCredentialsWithCurrentSetting()

        let store = KeychainCredentialStore(service: service)
        #expect(
            store.isSynchronizable(
                key: KeychainCredentialStore.credentialKey(scope: "identity-A", accountID: account.id)
            ) == true
        )

        credentials.deleteCredential(for: account)
        store.delete(key: KeychainCredentialStore.legacyKey(instanceID: instanceID))
    }

    @Test("A sibling sign-in does not retire the adopter's marker")
    func siblingSignInLeavesTheAdoptionMarkerAlone() {
        let service = makeService()
        let markers = makeMarkers()
        let instanceID = UUID()
        let adopter = Account.migrated(from: instanceID)
        // A second login the user adds on the same instance.
        let sibling = Account(instanceID: instanceID)
        seedLegacyItem(service: service, instanceID: instanceID, value: "legacy-secret")

        let credentials = makeCredentials(service: service, scope: "identity-A", markers: markers)
        #expect(credentials.adoptLegacyCredential(for: adopter) == true)

        // Signing the sibling in says nothing about the account that adopted
        // this instance's pre-revamp secret.
        credentials.setCredential("sibling-secret", for: sibling)
        #expect(markers.hasAdopted(service: service, instanceID: instanceID, scope: "identity-A") == true)

        // So the adopter can still retire the legacy item when it is deleted —
        // matching on the instance alone silently withdrew that claim.
        credentials.deleteLegacyCredentialIfOwned(for: adopter)
        #expect(legacyValue(service: service, instanceID: instanceID) == nil)

        credentials.deleteCredential(for: adopter)
        credentials.deleteCredential(for: sibling)
    }

    @Test("A login the user added themselves never inherits the legacy item")
    func onlyTheMigratedAccountAdopts() {
        let service = makeService()
        let instanceID = UUID()
        // Not `Account.migrated`: a second login on the same instance, created
        // by signing in. The legacy item is keyed by instance, so without the
        // migrated-account rule this one would match it.
        let sibling = Account(instanceID: instanceID)
        seedLegacyItem(service: service, instanceID: instanceID, value: "legacy-secret")

        let credentials = makeCredentials(service: service, scope: "identity-A", markers: makeMarkers())

        #expect(credentials.hasAdoptableLegacyCredential(for: sibling) == false)
        #expect(credentials.adoptLegacyCredential(for: sibling) == false)
        #expect(credentials.credential(for: sibling) == nil)

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

    @Test("Adoption in one backend does not suppress the other's offer")
    func markersAreNamespacedByService() {
        // Both credential managers share one marker store, and an instance UUID
        // can outlive a change of backend.
        let invidiousService = makeService()
        let pipedService = makeService()
        let markers = makeMarkers()
        let instanceID = UUID()
        let account = Account.migrated(from: instanceID)

        seedLegacyItem(service: invidiousService, instanceID: instanceID, value: "invidious-sid")
        seedLegacyItem(service: pipedService, instanceID: instanceID, value: "piped-token")

        let invidious = makeCredentials(service: invidiousService, scope: "identity-A", markers: markers)
        let piped = makeCredentials(service: pipedService, scope: "identity-A", markers: markers)

        #expect(invidious.adoptLegacyCredential(for: account) == true)

        // Piped's own legacy item is untouched and still offered.
        #expect(piped.hasAdoptableLegacyCredential(for: account) == true)
        #expect(piped.adoptLegacyCredential(for: account) == true)
        #expect(piped.credential(for: account) == "piped-token")
        #expect(invidious.credential(for: account) == "invidious-sid")

        // Each deletion consults its own marker and its own secret.
        invidious.deleteLegacyCredentialIfOwned(for: account)
        #expect(legacyValue(service: invidiousService, instanceID: instanceID) == nil)
        #expect(legacyValue(service: pipedService, instanceID: instanceID) == "piped-token")

        piped.deleteLegacyCredentialIfOwned(for: account)
        #expect(legacyValue(service: pipedService, instanceID: instanceID) == nil)

        invidious.deleteCredential(for: account)
        piped.deleteCredential(for: account)
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

@Suite("Credential replacement across devices")
@MainActor
struct CredentialReplacementTests {
    private func makeService() -> String {
        "com.yattee.tests.\(UUID().uuidString)"
    }

    private func makeMarkers() -> CredentialAdoptionMarkerStore {
        CredentialAdoptionMarkerStore(
            defaults: UserDefaults(suiteName: "yattee.tests.\(UUID().uuidString)")!
        )
    }

    /// One item's attributes, asked for in exactly one synchronizable form.
    ///
    /// The store deliberately matches both, so a test that wants to know which
    /// of the two answered has to ask for itself.
    private func attributes(service: String, key: String, synchronizable: Bool) -> [String: Any]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: synchronizable,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? [String: Any]
    }

    @Test("A credential that arrived from another device wins over a device-local copy")
    func synchronizableItemAnswersFirst() {
        let service = makeService()
        let store = KeychainCredentialStore(service: service)
        let key = KeychainCredentialStore.credentialKey(scope: "identity-A", accountID: UUID())

        // The sync flag is part of a generic password's primary key, so both of
        // these land — neither write displaces the other.
        #expect(store.addIfAbsent("kept-on-this-device", forKey: key, synchronizable: false) == errSecSuccess)
        #expect(store.addIfAbsent("arrived-from-elsewhere", forKey: key, synchronizable: true) == errSecSuccess)

        #expect(store.value(forKey: key) == "arrived-from-elsewhere")

        store.delete(key: key)
    }

    @Test("A device-local credential is still read when nothing has arrived")
    func localItemAnswersWhenAlone() {
        let service = makeService()
        let store = KeychainCredentialStore(service: service)
        let key = KeychainCredentialStore.credentialKey(scope: "identity-A", accountID: UUID())

        #expect(store.addIfAbsent("kept-on-this-device", forKey: key, synchronizable: false) == errSecSuccess)
        #expect(store.value(forKey: key) == "kept-on-this-device")

        store.delete(key: key)
    }

    @Test("Replacing a credential writes a new item rather than editing the old one")
    func replacementReplacesTheItem() {
        let service = makeService()
        let store = KeychainCredentialStore(service: service)
        let key = KeychainCredentialStore.credentialKey(scope: "identity-A", accountID: UUID())

        #expect(store.set("first-secret", forKey: key, synchronizable: true) == errSecSuccess)
        let created = attributes(service: service, key: key, synchronizable: true)?[
            kSecAttrCreationDate as String
        ] as? Date

        #expect(store.set("second-secret", forKey: key, synchronizable: true) == errSecSuccess)
        #expect(store.value(forKey: key) == "second-secret")

        // A fresh item, not the old one edited. This is the difference between
        // a sign-in the user's other devices receive and one they never hear
        // about: an in-place `SecItemUpdate` was measured not to propagate
        // through iCloud Keychain at all, while a replacement arrived in 15 s.
        let replaced = attributes(service: service, key: key, synchronizable: true)?[
            kSecAttrCreationDate as String
        ] as? Date
        #expect(created != nil)
        #expect(replaced != nil)
        #expect(replaced != created)

        store.delete(key: key)
    }

    @Test("Replacing a credential retires the twin in the other form")
    func replacementRetiresTheOtherForm() {
        let service = makeService()
        let store = KeychainCredentialStore(service: service)
        let key = KeychainCredentialStore.credentialKey(scope: "identity-A", accountID: UUID())

        #expect(store.addIfAbsent("kept-on-this-device", forKey: key, synchronizable: false) == errSecSuccess)
        #expect(store.set("signed-in-again", forKey: key, synchronizable: true) == errSecSuccess)

        #expect(attributes(service: service, key: key, synchronizable: false) == nil)
        #expect(store.value(forKey: key) == "signed-in-again")

        store.delete(key: key)
    }

    @Test("A sign-in on another device reaches an account that adopted its legacy login")
    func adoptedCredentialYieldsToAnArrivingOne() {
        let service = makeService()
        let store = KeychainCredentialStore(service: service)
        let instanceID = UUID()
        let account = Account.migrated(from: instanceID)

        store.set(
            "legacy-secret",
            forKey: KeychainCredentialStore.legacyKey(instanceID: instanceID),
            synchronizable: false
        )

        let credentials = AccountKeychainCredentials(
            service: service,
            credentialNoun: "credential",
            identityScope: CredentialIdentityScope(fixedScope: "identity-A"),
            markers: makeMarkers()
        )
        #expect(credentials.adoptLegacyCredential(for: account) == true)
        #expect(credentials.credential(for: account) == "legacy-secret")

        // The user signs in again on their other device. That credential
        // arrives as a synchronizable item under the very key the adopted copy
        // occupies, and the copy is device-local, so both sit there at once.
        // Reading the stale one is how a rejection the user already fixed
        // elsewhere would never lift here.
        let key = KeychainCredentialStore.credentialKey(scope: "identity-A", accountID: account.id)
        #expect(store.addIfAbsent("signed-in-elsewhere", forKey: key, synchronizable: true) == errSecSuccess)

        #expect(credentials.credential(for: account) == "signed-in-elsewhere")

        credentials.deleteCredential(for: account)
        store.delete(key: KeychainCredentialStore.legacyKey(instanceID: instanceID))
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
        var availability: CloudKitIdentity.AccountAvailability = .available
        /// User record returned when there is no ubiquity token to key on.
        var tokenlessRecord: String?
        var onResolveStart: (() -> Void)?
        var switchTask: Task<Void, Never>?

        func resolve() async -> String? {
            // Snapshotted before the hook runs, so a switch staged inside it
            // yields a genuinely stale result rather than the new value.
            let tokenless = tokenlessRecord
            onResolveStart?()
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                return nil
            }
            guard let fingerprint else { return tokenless }
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
            accountAvailabilityProvider: { harness.availability },
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
            accountAvailabilityProvider: { harness.availability },
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
            accountAvailabilityProvider: { harness.availability },
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

    @Test("A missing ubiquity token alone never scopes to local")
    func missingTokenDoesNotImplySignedOut() async {
        // iCloud Drive off while still signed in: Foundation returns no token,
        // but the account is real. Scoping to local here would put two
        // different Apple accounts in one namespace.
        let harness = Harness()
        harness.fingerprint = nil
        harness.availability = .available
        harness.resultsByFingerprint = [:]

        let scope = CredentialIdentityScope(
            defaults: makeDefaults(),
            fingerprintProvider: { harness.fingerprint },
            resolveUserRecordID: { "_recordA" },
            accountAvailabilityProvider: { harness.availability },
            retryDelay: { _ in }
        )

        #expect(scope.current == nil)
        await scope.resolve()
        #expect(scope.current == "_recordA")
        #expect(scope.current != CredentialIdentityScope.localScope)
    }

    @Test("Signing out scopes to local, confirmed by CloudKit")
    func signedOutUsesLocalScope() async {
        let harness = Harness()
        harness.fingerprint = nil
        harness.availability = .noAccount

        let scope = CredentialIdentityScope(
            defaults: makeDefaults(),
            fingerprintProvider: { harness.fingerprint },
            resolveUserRecordID: { await harness.resolve() },
            accountAvailabilityProvider: { harness.availability },
            retryDelay: { _ in }
        )

        // Not assumed up front — only CloudKit can tell "signed out" from
        // "token unavailable".
        #expect(scope.current == nil)
        await scope.resolve()
        #expect(scope.current == CredentialIdentityScope.localScope)
    }

    @Test("A tokenless scope is re-pointed when the account changes silently")
    func tokenlessScopeIsRevalidated() async {
        // iCloud Drive off: the token stays nil across the switch, so nothing
        // local changes and no ubiquity notification fires.
        let harness = Harness()
        harness.fingerprint = nil
        harness.availability = .available

        harness.tokenlessRecord = "_recordA"
        let scope = CredentialIdentityScope(
            defaults: makeDefaults(),
            fingerprintProvider: { harness.fingerprint },
            resolveUserRecordID: { harness.tokenlessRecord },
            accountAvailabilityProvider: { harness.availability },
            retryDelay: { _ in }
        )

        await scope.resolve()
        #expect(scope.current == "_recordA")

        // The user switches to account B and returns to the app.
        harness.tokenlessRecord = "_recordB"
        await scope.resolveIfNeeded()
        #expect(scope.current == "_recordB")
    }

    @Test("A tokenless scope falls back to local once the account is gone")
    func tokenlessScopeFallsBackOnSignOut() async {
        let harness = Harness()
        harness.fingerprint = nil
        harness.availability = .available

        let scope = CredentialIdentityScope(
            defaults: makeDefaults(),
            fingerprintProvider: { harness.fingerprint },
            resolveUserRecordID: { "_recordA" },
            accountAvailabilityProvider: { harness.availability },
            retryDelay: { _ in }
        )

        await scope.resolve()
        #expect(scope.current == "_recordA")

        harness.availability = .noAccount
        await scope.resolveIfNeeded()
        #expect(scope.current == CredentialIdentityScope.localScope)
    }

    @Test("A token-derived scope is not re-checked on every activation")
    func tokenDerivedScopeIsStable() async {
        let harness = Harness()
        harness.resultsByFingerprint = ["identity-A": "_recordA"]

        let scope = CredentialIdentityScope(
            defaults: makeDefaults(),
            fingerprintProvider: { harness.fingerprint },
            resolveUserRecordID: { await harness.resolve() },
            accountAvailabilityProvider: { harness.availability },
            retryDelay: { _ in }
        )

        await scope.resolve()
        #expect(scope.current == "_recordA")

        // A token-backed scope changes only via the notification, so a
        // foreground pass must leave it exactly as it was.
        harness.resultsByFingerprint = ["identity-A": "_somethingElse"]
        await scope.resolveIfNeeded()
        #expect(scope.current == "_recordA")
    }

    @Test("A tokenless scope is dropped, not served, while it is unconfirmed")
    func tokenlessScopeIsNotServedWhileUnconfirmed() async {
        let harness = Harness()
        harness.fingerprint = nil
        harness.availability = .available
        harness.tokenlessRecord = "_recordA"

        let scope = CredentialIdentityScope(
            defaults: makeDefaults(),
            fingerprintProvider: { harness.fingerprint },
            resolveUserRecordID: { harness.tokenlessRecord },
            accountAvailabilityProvider: { harness.availability },
            retryDelay: { _ in }
        )

        await scope.resolve()
        #expect(scope.current == "_recordA")

        // Foregrounding with CloudKit unreachable must not keep serving A —
        // the account may have changed while the app was suspended.
        harness.availability = .indeterminate
        await scope.resolveIfNeeded()
        #expect(scope.current == nil)
    }

    @Test("A stale tokenless lookup is refused after an account change")
    func staleTokenlessLookupIsRefused() async {
        // Both before and after the switch the fingerprint is nil, so only a
        // generation counter can tell the two lookups apart.
        let harness = Harness()
        harness.fingerprint = nil
        harness.availability = .available
        harness.tokenlessRecord = "_recordA"

        let scope = CredentialIdentityScope(
            defaults: makeDefaults(),
            fingerprintProvider: { harness.fingerprint },
            resolveUserRecordID: { await harness.resolve() },
            accountAvailabilityProvider: { harness.availability },
            retryDelay: { _ in }
        )

        // CKAccountChanged lands while A's lookup is in flight.
        harness.onResolveStart = { [weak scope] in
            harness.onResolveStart = nil
            MainActor.assumeIsolated {
                harness.tokenlessRecord = "_recordB"
                scope?.identityDidChange(source: "test")
            }
        }

        await scope.resolve()

        // The decisive assertion: A's result must not be accepted just because
        // nil == nil on both sides of the switch.
        #expect(scope.current != "_recordA")

        // Then the replay lands on B (driven here rather than awaiting the
        // observer's detached task).
        await scope.resolveIfNeeded()
        #expect(scope.current == "_recordB")
    }

    @Test("An account change restores the retry budget")
    func identityChangeResetsAttemptBudget() async {
        let harness = Harness()
        harness.fingerprint = nil
        harness.availability = .available
        harness.tokenlessRecord = "_recordA"
        harness.failuresRemaining = 99 // exhaust every attempt for this identity

        let scope = CredentialIdentityScope(
            defaults: makeDefaults(),
            fingerprintProvider: { harness.fingerprint },
            resolveUserRecordID: { await harness.resolve() },
            accountAvailabilityProvider: { harness.availability },
            retryDelay: { _ in }
        )

        await scope.resolve()
        #expect(scope.current == nil)

        // A different account signs in. Its lookup must not inherit an
        // exhausted budget and give up without trying.
        harness.failuresRemaining = 0
        harness.tokenlessRecord = "_recordB"
        scope.identityDidChange(source: "test")
        await scope.resolve()

        #expect(scope.current == "_recordB")
    }

    @Test("An undeterminable account status leaves the scope unresolved")
    func indeterminateStatusStaysUnresolved() async {
        let harness = Harness()
        harness.fingerprint = nil
        harness.availability = .indeterminate

        let scope = CredentialIdentityScope(
            defaults: makeDefaults(),
            fingerprintProvider: { harness.fingerprint },
            resolveUserRecordID: { "_shouldNotBeUsed" },
            accountAvailabilityProvider: { harness.availability },
            retryDelay: { _ in }
        )

        await scope.resolve()
        #expect(scope.current == nil)
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
            accountAvailabilityProvider: { harness.availability },
            retryDelay: { _ in }
        )
        await first.resolve()
        #expect(first.current == "_recordA")

        // Relaunch: no network involved this time.
        let second = CredentialIdentityScope(
            defaults: defaults,
            fingerprintProvider: { harness.fingerprint },
            resolveUserRecordID: { nil },
            accountAvailabilityProvider: { harness.availability },
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
