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

        // Whatever *this account* adopted is gone, replaced by a login the user
        // just proved they hold. Leaving the marker would keep it out of the
        // resync that follows the iCloud toggle, so the new credential would
        // stay on this device and every other one would show an account it
        // never receives a login for. It would also let a deletion retire an
        // unscoped item this account no longer has anything to do with.
        //
        // A sibling's marker is left strictly alone: signing a second login
        // into the same instance says nothing about the account that adopted
        // that instance's pre-revamp secret.
        markers.removeMarker(
            service: store.service,
            instanceID: account.instanceID,
            accountID: account.id,
            scope: scope
        )

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

    /// Rewrites the stored credentials so they carry the current sync setting.
    ///
    /// `kSecAttrSynchronizable` is fixed when an item is written, so a login
    /// stored while iCloud sync was off stays local forever. Enabling sync
    /// afterwards uploads the account metadata, and every other device would
    /// then show an account whose credential never arrives. Called when the
    /// user turns sync on.
    func resyncCredentialsWithCurrentSetting() {
        guard let scope = identityScope.current else { return }

        let syncEnabled = shouldSyncToiCloud
        // An adopted legacy secret is deliberately kept on this device (see
        // `adoptLegacyCredential`). Rewriting it here would undo that: the
        // toggle would push a credential of unknown provenance into whichever
        // iCloud Keychain is current, which is the one thing silent adoption is
        // careful not to do. Nothing is lost — the legacy item it was copied
        // from already syncs, so the user's other devices adopt their own copy.
        let adopted = markers.adoptedAccountIDs(service: store.service, scope: scope)

        for accountID in loginsByScope[scope] ?? [] where !adopted.contains(accountID) {
            let credentialKey = KeychainCredentialStore.credentialKey(scope: scope, accountID: accountID)

            // The marker is written *after* the copy it describes, so a launch
            // that ends in between leaves an adopted credential no marker will
            // ever claim — and adoption will not retry, because the key is no
            // longer empty. Recognising the value itself closes that gap: a
            // scoped credential identical to the unscoped item it could only
            // have come from is an adopted copy, marker or not. Migrated
            // accounts reuse their instance's UUID, which is what the legacy
            // key is made of, and they are the only accounts allowed to adopt.
            if let stored = store.value(forKey: credentialKey),
               stored == store.value(forKey: KeychainCredentialStore.legacyKey(instanceID: accountID)) {
                continue
            }

            rewrite(key: credentialKey, synchronizable: syncEnabled)
            rewrite(
                key: KeychainCredentialStore.usernameKey(scope: scope, accountID: accountID),
                synchronizable: syncEnabled
            )
        }
    }

    /// Rewrites one item so it carries the wanted sync flag.
    ///
    /// Skipped when the flag already matches: the only way to change it is to
    /// delete and re-add, which risks the login for no reason — and deleting a
    /// synchronizable item propagates to every device. If the re-add does fail,
    /// the original is put back the way it was rather than left missing.
    private func rewrite(key: String, synchronizable: Bool) {
        guard let value = store.value(forKey: key) else { return }

        let current = store.isSynchronizable(key: key)
        guard current != synchronizable else { return }

        let status = store.set(value, forKey: key, synchronizable: synchronizable)
        guard status != errSecSuccess else { return }

        let restored = store.set(value, forKey: key, synchronizable: current ?? false)
        LoggingService.shared.error(
            restored == errSecSuccess
                ? "Could not change how a \(credentialNoun) syncs — left it as it was"
                : "Could not change how a \(credentialNoun) syncs, and could not restore it",
            category: .keychain,
            details: "status=\(store.describe(status))"
        )
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

    // MARK: - Identity migration

    /// Moves an account's credential and username out of `sourceScope` and into
    /// the scope that is current now.
    ///
    /// For accounts created while no Apple account was available: they live in
    /// the `local` namespace, and the credential keyed `local|<accountID>` has
    /// to follow the record when an identity claims it. Written the way a fresh
    /// sign-in under this identity would write it, with three protections:
    /// `addIfAbsent` so a credential already held under the current scope is
    /// never clobbered (decision 5), a read-back before anything is deleted, and
    /// the source left completely untouched on any failure so the next sweep can
    /// try again.
    ///
    /// - Returns: `true` only when `sourceScope` really holds nothing for this
    ///   account any more: the target credential verified (or there was never
    ///   one to move), the source items are gone, and the username pair is
    ///   settled the same way. `false` means something is still keyed to the
    ///   source, so the caller must not prune the record that points at it —
    ///   that record is the only thing that will bring a retry back here.
    @discardableResult
    func migrateCredential(forAccountID accountID: UUID, fromScope sourceScope: String) -> Bool {
        guard let scope = currentScope() else { return false }
        // Nothing to move, and moving would delete what it had just written.
        guard sourceScope != scope else { return true }

        let sourceKey = KeychainCredentialStore.credentialKey(scope: sourceScope, accountID: accountID)
        let targetKey = KeychainCredentialStore.credentialKey(scope: scope, accountID: accountID)

        guard let secret = store.value(forKey: sourceKey) else {
            // An account that was never signed in under the source scope. Its
            // username still moves — it is what the sign-in sheet prefills —
            // and the record may only be pruned once that move is settled too.
            loginsByScope[sourceScope]?.remove(accountID)
            let usernameSettled = migrateUsername(forAccountID: accountID, from: sourceScope, to: scope)
            // Or a previous attempt moved the secret and died before the marker
            // that describes where it went.
            carryAdoptionProvenance(forAccountID: accountID, from: sourceScope, to: scope)
            return usernameSettled
        }

        // Decision 5: a credential already stored under the current identity was
        // written by a sign-in this Apple account actually made, so the copy
        // being migrated is redundant rather than a replacement.
        if store.value(forKey: targetKey) != nil {
            let usernameSettled = migrateUsername(forAccountID: accountID, from: sourceScope, to: scope)
            let sourceCleared = removed(key: sourceKey)
            loginsByScope[scope, default: []].insert(accountID)
            if sourceCleared { loginsByScope[sourceScope]?.remove(accountID) }

            // "Already occupied" is not always somebody else's sign-in: it is
            // also what a previous attempt at *this* move looks like when it
            // died between the verified copy and the marker that records where
            // the copy went. Left unrepaired, the next resync would read an
            // unmarked credential as one the user proved they hold and upload
            // an adopted secret into this identity's iCloud Keychain. The
            // fingerprint tells the two apart.
            carryAdoptionProvenance(forAccountID: accountID, from: sourceScope, to: scope)

            guard usernameSettled, sourceCleared else {
                LoggingService.shared.error(
                    "A redundant \(credentialNoun) could not be cleared out of the namespace being left",
                    category: .keychain,
                    details: "accountID=\(accountID), from=\(sourceScope)"
                )
                return false
            }

            LoggingService.shared.info(
                "Dropped a \(credentialNoun) made redundant by one already held under this identity",
                category: .keychain,
                details: "accountID=\(accountID), from=\(sourceScope)"
            )
            return true
        }

        // A secret adopted from the pre-revamp unscoped item keeps its
        // provenance across the move: `adoptLegacyCredential` deliberately
        // writes it device-local so a login of unproven origin never reaches an
        // iCloud Keychain, and re-filing it as synchronizable here would undo
        // exactly that. Markers are keyed by instance, and only a migrated
        // account — whose ID *is* its instance's — is ever allowed to adopt, so
        // the account ID is the right instance to ask about.
        let wasAdopted = markers.hasAdopted(
            service: store.service,
            instanceID: accountID,
            scope: sourceScope
        )
        let syncEnabled = wasAdopted ? false : shouldSyncToiCloud

        let status = store.addIfAbsent(secret, forKey: targetKey, synchronizable: syncEnabled)
        guard status == errSecSuccess else {
            LoggingService.shared.error(
                "Could not move a \(credentialNoun) into the current identity — leaving it where it is",
                category: .keychain,
                details: "accountID=\(accountID), from=\(sourceScope), status=\(store.describe(status))"
            )
            return false
        }

        // Verified before the source is deleted, the same way legacy adoption
        // is: a write that reports success and reads back as something else is
        // the one case where deleting the source would lose the credential
        // outright. Whatever is there is left alone and the source stands, so
        // the next sweep resolves it — as a redundant copy if a real credential
        // arrived in the gap.
        guard store.value(forKey: targetKey) == secret else {
            LoggingService.shared.error(
                "A moved \(credentialNoun) did not verify — the source is left for the next attempt",
                category: .keychain,
                details: "accountID=\(accountID), from=\(sourceScope)"
            )
            return false
        }

        let usernameSettled = migrateUsername(forAccountID: accountID, from: sourceScope, to: scope)
        let sourceCleared = removed(key: sourceKey)

        // Recorded on the strength of the verified copy, not of the cleanup
        // that follows it: the marker has to describe where the adopted copy
        // now lives, or the deletion that retires the unscoped item would no
        // longer recognise it as this account's to retire.
        carryAdoptionProvenance(forAccountID: accountID, from: sourceScope, to: scope)

        loginsByScope[scope, default: []].insert(accountID)
        if sourceCleared { loginsByScope[sourceScope]?.remove(accountID) }

        guard usernameSettled, sourceCleared else {
            // The credential is safely under this identity, but something is
            // still filed under the one being left. Reporting success would
            // prune the record that names it and strand that item forever, so
            // the sweep is told to come back: the retry finds the target
            // credential in place and only has the leftovers to clear.
            LoggingService.shared.error(
                "A moved \(credentialNoun) left something behind in the namespace being left",
                category: .keychain,
                details: "accountID=\(accountID), from=\(sourceScope)"
            )
            return false
        }

        LoggingService.shared.info(
            "Moved a \(credentialNoun) into the current identity",
            category: .keychain,
            details: "accountID=\(accountID), from=\(sourceScope), iCloudSync=\(syncEnabled)"
        )
        return true
    }

    /// Re-files an adoption marker under the scope its credential now lives in.
    ///
    /// A marker is the only thing that says a credential was *adopted* — copied
    /// from the pre-revamp unscoped item rather than signed in for. That claim
    /// has to follow the secret across a namespace move, because everything
    /// downstream reads it: `resyncCredentialsWithCurrentSetting` leaves adopted
    /// copies device-local instead of uploading a secret of unproven provenance
    /// into an iCloud Keychain, and `canDeleteLegacyItem` needs it to recognise
    /// the unscoped item as this account's to retire.
    ///
    /// Called from every path a migration can settle through, not just the one
    /// that does the copying, because a move is several Keychain calls and any
    /// of them can be the last one before the process dies. A retry then finds
    /// the target already holding the secret and would otherwise report success
    /// while the provenance stayed behind under a namespace nothing reads again.
    ///
    /// What makes that safe to repair blind is the fingerprint: the marker is
    /// bound to one value, so a target credential that still fingerprints the
    /// same is the adopted copy, and a different one is a real sign-in this
    /// identity made — which the adopted copy was merely redundant beside, and
    /// which nothing about the adoption applies to.
    private func carryAdoptionProvenance(forAccountID accountID: UUID, from sourceScope: String, to scope: String) {
        // Markers are keyed by instance, and only a migrated account — whose ID
        // *is* its instance's — is ever allowed to adopt, so the account ID is
        // the right instance to ask about.
        guard markers.hasAdopted(service: store.service, instanceID: accountID, scope: sourceScope) else { return }

        let targetKey = KeychainCredentialStore.credentialKey(scope: scope, accountID: accountID)

        // Equality with the marker's fingerprint is taken as proof that this
        // value *is* the legacy secret, however it got here — so it is treated
        // as adopted and kept device-local. That rests on both supported
        // backends minting a fresh secret for every login: Invidious issues a
        // per-session SID, and a Piped JWT differs per issue through its `iat`.
        // Two separate logins therefore cannot collide on one value, so a match
        // can only be the adopted copy rather than a sign-in that happens to
        // look like it. A future backend that can hand back an identical
        // credential for a separate login breaks that reasoning and needs a
        // different discriminator here — the fingerprint alone would then
        // misread a genuine login as adopted and keep it off iCloud Keychain.
        if let stored = store.value(forKey: targetKey),
           markers.hasAdopted(
               service: store.service,
               instanceID: accountID,
               scope: sourceScope,
               matching: stored
           ) {
            markers.record(
                service: store.service,
                instanceID: accountID,
                accountID: accountID,
                scope: scope,
                secret: stored
            )

            // And the copy itself stays where adoption put it. A repair reached
            // through a path that never chose the sync flag — or after a resync
            // that ran while the marker was missing — could be looking at an
            // item marked synchronizable, which is the one thing an adopted
            // secret must not be.
            rewrite(key: targetKey, synchronizable: false)
        }

        // Retired only once the copy it described is really gone. While the
        // source item survives — a deletion the Keychain refused — the marker
        // is still the truth about it, and the sweep is coming back anyway.
        guard store.value(
            forKey: KeychainCredentialStore.credentialKey(scope: sourceScope, accountID: accountID)
        ) == nil else { return }

        markers.removeMarker(
            service: store.service,
            instanceID: accountID,
            accountID: accountID,
            scope: sourceScope
        )
    }

    /// Moves the username item, which is a convenience rather than a secret.
    ///
    /// Counts towards the migration's success all the same. Not because a
    /// prefilled field is worth a retry, but because the record being imported
    /// is the only thing that ever brings the sweep back to this key: prune it
    /// while `<source>|<id>#username` still exists and that item is orphaned for
    /// good, under a namespace nothing will read again.
    ///
    /// - Returns: whether the source scope is done with this account's username
    ///   — nothing to move, or the target holds one and the source item is gone.
    private func migrateUsername(forAccountID accountID: UUID, from sourceScope: String, to scope: String) -> Bool {
        let sourceKey = KeychainCredentialStore.usernameKey(scope: sourceScope, accountID: accountID)
        guard let username = store.value(forKey: sourceKey) else { return true }

        let targetKey = KeychainCredentialStore.usernameKey(scope: scope, accountID: accountID)
        if store.value(forKey: targetKey) == nil {
            store.addIfAbsent(username, forKey: targetKey, synchronizable: shouldSyncToiCloud)
        }

        guard store.value(forKey: targetKey) != nil else {
            LoggingService.shared.error(
                "A login identifier could not be moved into the current identity",
                category: .keychain,
                details: "accountID=\(accountID), from=\(sourceScope)"
            )
            return false
        }
        return removed(key: sourceKey)
    }

    /// Deletes a Keychain item, reading "there was nothing there" as done.
    ///
    /// Every caller here is clearing a key out of a namespace being left, and
    /// for that question an absent item and a deleted one are the same answer.
    /// Anything else is a real failure the sweep has to retry — the item would
    /// otherwise outlive the record that knows to come back for it.
    private func removed(key: String) -> Bool {
        let status = store.delete(key: key)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            LoggingService.shared.error(
                "Could not delete a Keychain item",
                category: .keychain,
                details: "status=\(store.describe(status))"
            )
            return false
        }
        return true
    }

    /// Deletes an account's credential and username under a scope that is not
    /// necessarily the current one.
    ///
    /// For the import sweep's tombstone rule: an account this identity has
    /// deliberately deleted is never imported, and the secret it was keyed to
    /// goes with the record rather than sitting under a namespace nothing will
    /// read again.
    ///
    /// - Returns: whether that scope now holds nothing for the account. `false`
    ///   keeps the local record where it is: it is the only thing that brings a
    ///   sweep back to these keys, so pruning it over a failed deletion would
    ///   strand the secret it refused.
    @discardableResult
    func deleteCredential(forAccountID accountID: UUID, inScope scope: String) -> Bool {
        let credentialCleared = removed(
            key: KeychainCredentialStore.credentialKey(scope: scope, accountID: accountID)
        )
        let usernameCleared = removed(
            key: KeychainCredentialStore.usernameKey(scope: scope, accountID: accountID)
        )

        if credentialCleared {
            loginsByScope[scope]?.remove(accountID)

            // Its marker described a copy that no longer exists. Keyed by
            // instance, and only a migrated account can have adopted anything,
            // so the account ID is the instance to name here. Kept while the
            // copy is still there: it is the only record of where that secret
            // came from, and the retry that deletes it still needs it.
            markers.removeMarker(
                service: store.service,
                instanceID: accountID,
                accountID: accountID,
                scope: scope
            )
        }

        guard credentialCleared, usernameCleared else {
            LoggingService.shared.error(
                "A refused import's \(credentialNoun) could not be deleted — leaving it for the next sweep",
                category: .keychain,
                details: "accountID=\(accountID), scope=\(scope)"
            )
            return false
        }

        LoggingService.shared.info(
            "Deleted a \(credentialNoun) left behind by a refused import",
            category: .keychain,
            details: "accountID=\(accountID), scope=\(scope)"
        )
        return true
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
        // Only the account this instance's pre-revamp login became may inherit
        // its secret. The legacy item is keyed by instance, so any
        // credential-less account on the instance would otherwise match — and a
        // second login the user added themselves would silently come up holding
        // somebody else's session.
        guard account.isMigrated else { return false }
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
    ///
    /// The copy is written **device-local**, whatever the sync setting says.
    /// The pre-revamp release read its unscoped item with
    /// `kSecAttrSynchronizableAny` and no identity in the key, so a credential
    /// retained across an Apple Account change is already served to whoever
    /// holds the device — this migration does not widen that. What it must not
    /// do is re-file that secret as synchronizable under the identity that is
    /// current now, which would upload a login of unproven provenance into that
    /// person's iCloud Keychain and spread it to their other devices. Keeping
    /// the copy local costs the genuine owner nothing: their legacy item syncs,
    /// so every device of theirs finds it and adopts its own copy.
    @discardableResult
    func adoptLegacyCredential(for account: Account) -> Bool {
        guard let scope = currentScope() else { return false }
        guard account.isMigrated else { return false }
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
        let status = store.addIfAbsent(legacy, forKey: key, synchronizable: false)

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
        markers.removeMarker(
            service: store.service,
            instanceID: account.instanceID,
            accountID: account.id,
            scope: scope
        )

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
