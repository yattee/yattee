//
//  AccountKeychainCredentials.swift
//  Yattee
//
//  Shared implementation of account-keyed, identity-scoped credential storage.
//

import Foundation

/// The engine behind `AccountCredentialsManager`.
///
/// Both credential managers own one of these and forward to it, so the scoping
/// rules and the legacy-adoption protocol exist in exactly one place.
@MainActor
@Observable
final class AccountKeychainCredentials {
    private let store: KeychainCredentialStore
    private let identityScope: CredentialIdentityScope
    private let markers: CredentialAdoptionMarkerStore

    /// Name used in log lines ("SID", "token") so messages read naturally for
    /// whichever backend owns this instance.
    private let credentialNoun: String

    /// Known logins, partitioned by the identity scope they were observed under.
    ///
    /// Keyed rather than invalidated: a switch of Apple account (or the first
    /// resolution completing) must never let one identity's cache answer for
    /// another, and clearing a shared cache would mean mutating observable
    /// state from inside read methods a view body can call.
    private var loginsByScope: [String: Set<UUID>] = [:]

    /// Accounts holding a credential under the current identity.
    var loggedInAccountIDs: Set<UUID> {
        guard let scope = identityScope.current else { return [] }
        return loginsByScope[scope] ?? []
    }

    weak var settingsManager: SettingsManager?

    init(
        service: String,
        credentialNoun: String,
        identityScope: CredentialIdentityScope,
        markers: CredentialAdoptionMarkerStore? = nil
    ) {
        store = KeychainCredentialStore(service: service)
        self.credentialNoun = credentialNoun
        self.identityScope = identityScope
        self.markers = markers ?? CredentialAdoptionMarkerStore()
    }

    var isScopeResolved: Bool { identityScope.isResolved }

    /// Credentials sync to iCloud Keychain on the same toggle as the instances
    /// they belong to.
    private var shouldSyncToiCloud: Bool {
        settingsManager?.iCloudSyncEnabled == true && settingsManager?.syncInstances == true
    }

    private func currentScope() -> String? {
        identityScope.current
    }

    // MARK: - Credentials

    func setCredential(_ credential: String, for account: Account) {
        guard let scope = currentScope() else {
            LoggingService.shared.error(
                "Refusing to store \(credentialNoun) before the identity scope is resolved",
                category: .keychain,
                details: "accountID=\(account.id)"
            )
            return
        }

        let syncEnabled = shouldSyncToiCloud
        let status = store.set(
            credential,
            forKey: KeychainCredentialStore.credentialKey(scope: scope, accountID: account.id),
            synchronizable: syncEnabled
        )

        guard status == errSecSuccess else {
            LoggingService.shared.error(
                "Failed to store \(credentialNoun)",
                category: .keychain,
                details: "accountID=\(account.id), status=\(store.describe(status))"
            )
            return
        }

        loginsByScope[scope, default: []].insert(account.id)

        LoggingService.shared.info(
            "Stored \(credentialNoun)",
            category: .keychain,
            details: "accountID=\(account.id), iCloudSync=\(syncEnabled)"
        )
    }

    func credential(for account: Account) -> String? {
        guard let scope = currentScope() else { return nil }
        return store.value(
            forKey: KeychainCredentialStore.credentialKey(scope: scope, accountID: account.id)
        )
    }

    func deleteCredential(for account: Account) {
        deleteCredential(forAccountID: account.id)
        HomeInstanceCache.shared.clear(instanceID: account.instanceID, contentType: .feed)
    }

    func deleteCredential(forAccountID accountID: UUID) {
        guard let scope = currentScope() else { return }

        store.delete(key: KeychainCredentialStore.credentialKey(scope: scope, accountID: accountID))
        store.delete(key: KeychainCredentialStore.usernameKey(scope: scope, accountID: accountID))
        loginsByScope[scope]?.remove(accountID)

        LoggingService.shared.info(
            "Deleted \(credentialNoun)",
            category: .keychain,
            details: "accountID=\(accountID)"
        )
    }

    // MARK: - Username

    func setUsername(_ username: String, for account: Account) {
        guard let scope = currentScope() else { return }
        store.set(
            username,
            forKey: KeychainCredentialStore.usernameKey(scope: scope, accountID: account.id),
            synchronizable: shouldSyncToiCloud
        )
    }

    func username(for account: Account) -> String? {
        guard let scope = currentScope() else { return nil }
        return store.value(
            forKey: KeychainCredentialStore.usernameKey(scope: scope, accountID: account.id)
        )
    }

    // MARK: - Status

    func isLoggedIn(for account: Account) -> Bool {
        guard let scope = currentScope() else { return false }

        if loginsByScope[scope]?.contains(account.id) == true {
            return true
        }

        let hasCredential = credential(for: account) != nil
        if hasCredential {
            loginsByScope[scope, default: []].insert(account.id)
        }
        return hasCredential
    }

    func refreshLoginStatus(for account: Account) {
        guard let scope = currentScope() else { return }

        if credential(for: account) != nil {
            loginsByScope[scope, default: []].insert(account.id)
        } else {
            loginsByScope[scope]?.remove(account.id)
        }
    }

    // MARK: - Legacy adoption

    func hasAdoptableLegacyCredential(for account: Account) -> Bool {
        guard let scope = currentScope() else { return false }
        guard !markers.hasAdopted(service: store.service, instanceID: account.instanceID, scope: scope) else { return false }
        guard credential(for: account) == nil else { return false }

        return legacyCredential(for: account) != nil
    }

    /// Copies the legacy item into this account's scoped key.
    ///
    /// Copies — never moves. Deleting a synchronizable item propagates to every
    /// device signed in to the same Apple account, so removing the legacy item
    /// here would log the user out of devices still running the previous
    /// release, mid-rollout. It is retained until the account is really
    /// deleted; general cleanup waits for a compatibility-breaking release.
    @discardableResult
    func adoptLegacyCredential(for account: Account) -> Bool {
        guard let scope = currentScope() else { return false }
        guard !markers.hasAdopted(service: store.service, instanceID: account.instanceID, scope: scope) else { return false }
        guard let legacy = legacyCredential(for: account) else { return false }

        // Eligibility is re-checked here, not just when the offer was rendered:
        // iCloud Keychain may have delivered the real credential in between, and
        // replacing it with the older legacy secret would be a silent downgrade.
        guard credential(for: account) == nil else {
            LoggingService.shared.info(
                "Skipping legacy \(credentialNoun) adoption — a scoped credential already arrived",
                category: .keychain,
                details: "accountID=\(account.id)"
            )
            return false
        }

        let key = KeychainCredentialStore.credentialKey(scope: scope, accountID: account.id)
        let status = store.addIfAbsent(legacy, forKey: key, synchronizable: shouldSyncToiCloud)

        // A duplicate means a scoped credential landed between the check above
        // and this write — leave it strictly alone, it is newer than the legacy
        // secret.
        guard status == errSecSuccess else {
            LoggingService.shared.error(
                "Legacy \(credentialNoun) adoption did not write",
                category: .keychain,
                details: "accountID=\(account.id), status=\(store.describe(status))"
            )
            return false
        }

        // The marker is only written after the scoped copy reads back: a marker
        // for a credential that never landed would suppress the adoption offer
        // and strand the user with no way to sign in short of retyping.
        let readback = store.value(forKey: key)

        guard readback == legacy else {
            // A *different* readable value means iCloud Keychain delivered a
            // credential for this key between the add and the read. It is newer
            // than the legacy secret and belongs to a live login, so it is left
            // strictly alone — deleting here would propagate through iCloud
            // Keychain and revoke it on every device.
            if readback != nil {
                LoggingService.shared.info(
                    "Legacy \(credentialNoun) adoption superseded by a credential that arrived mid-write",
                    category: .keychain,
                    details: "accountID=\(account.id)"
                )
                return false
            }

            // Nothing readable is there. Tempting to roll the write back, but a
            // delete cannot be conditioned on the value that was just read:
            // `SecItemDelete` ignores `kSecValueData` (measured — a delete
            // issued with a deliberately wrong value still removes the item),
            // so the rollback would be a blind delete of whatever occupies the
            // key by then, including a credential that arrived from another
            // device in the gap — and it would propagate. Nothing is deleted;
            // no marker is written, so the account simply stays signed out and
            // an ordinary sign-in (a replacing write) recovers it.
            LoggingService.shared.error(
                "Legacy \(credentialNoun) adoption failed verification — sign-in required",
                category: .keychain,
                details: "accountID=\(account.id)"
            )
            return false
        }

        markers.record(
            service: store.service,
            instanceID: account.instanceID,
            accountID: account.id,
            scope: scope,
            secret: legacy
        )
        loginsByScope[scope, default: []].insert(account.id)

        LoggingService.shared.info(
            "Adopted legacy \(credentialNoun) into the identity-scoped key",
            category: .keychain,
            details: "accountID=\(account.id), instanceID=\(account.instanceID)"
        )

        return true
    }

    func deleteLegacyCredentialIfOwned(for account: Account) {
        guard let scope = currentScope() else { return }

        let legacyKey = KeychainCredentialStore.legacyKey(instanceID: account.instanceID)
        let currentValue = store.value(forKey: legacyKey)

        guard markers.canDeleteLegacyItem(
            service: store.service,
            instanceID: account.instanceID,
            accountID: account.id,
            scope: scope,
            currentLegacyValue: currentValue
        ) else {
            LoggingService.shared.info(
                "Leaving the legacy \(credentialNoun) in place — not this account's to delete",
                category: .keychain,
                details: "instanceID=\(account.instanceID), accountID=\(account.id)"
            )
            return
        }

        // Re-read immediately before deleting. The Keychain offers no
        // compare-and-delete — `SecItemDelete` ignores `kSecValueData`
        // (measured) — so the fingerprint check above can only ever validate a
        // snapshot. Re-reading here shrinks the window to a single call gap and
        // catches a replacement that landed while the fingerprint was being
        // computed.
        //
        // A residual race remains by construction: if another device running
        // the previous release writes a new legacy value inside that gap, this
        // deletes their fresh login and the deletion propagates. Accepted —
        // closing it is not possible with these APIs, and the alternative
        // (never deleting) leaves a credential the user explicitly removed
        // sitting in their iCloud Keychain indefinitely.
        guard store.value(forKey: legacyKey) == currentValue else {
            LoggingService.shared.info(
                "Legacy \(credentialNoun) changed while being retired — leaving it in place",
                category: .keychain,
                details: "instanceID=\(account.instanceID)"
            )
            return
        }

        store.delete(key: legacyKey)
        markers.removeMarker(service: store.service, instanceID: account.instanceID, scope: scope)

        LoggingService.shared.info(
            "Deleted the legacy \(credentialNoun) alongside its account",
            category: .keychain,
            details: "instanceID=\(account.instanceID)"
        )
    }

    /// Reads the unscoped, pre-revamp item. Only the adoption paths call this.
    private func legacyCredential(for account: Account) -> String? {
        store.value(forKey: KeychainCredentialStore.legacyKey(instanceID: account.instanceID))
    }
}
