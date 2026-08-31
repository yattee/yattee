//
//  AccountCredentialsManager.swift
//  Yattee
//
//  Account-keyed credential storage — the multi-login replacement for the
//  instance-keyed InstanceCredentialsManager.
//

import Foundation

/// Credential storage keyed by `Account`, not by `Instance`.
///
/// Adopted by `InvidiousCredentialsManager` and `PipedCredentialsManager`.
/// `BasicAuthCredentialsManager` deliberately does **not** adopt it and keeps
/// `InstanceCredentialsManager`: HTTP Basic auth is a property of the instance
/// (or the reverse proxy in front of it), not of a user account, and a single
/// proxy credential covers every account on that instance.
@MainActor
protocol AccountCredentialsManager: AnyObject, Observable {
    /// Accounts with a stored credential under the **current** identity scope.
    var loggedInAccountIDs: Set<UUID> { get }

    /// Whether the identity scope has been resolved yet.
    ///
    /// While `false`, every read below reports "no credential" because the app
    /// cannot yet tell which scope to look in. Callers must render that as
    /// *temporarily unavailable*, never as "signed out" — correcting state on
    /// it would discard a perfectly good login.
    var isScopeResolved: Bool { get }

    func setCredential(_ credential: String, for account: Account)
    func credential(for account: Account) -> String?
    func deleteCredential(for account: Account)

    /// Deletes the credential and stored login identifier for an account this
    /// device may know nothing else about.
    ///
    /// A deletion can reach this device before the account it deletes does —
    /// the tombstone and the account are separate records, and iCloud Keychain
    /// runs on its own timeline. The secret must go regardless, and the scoped
    /// key needs only the account's ID.
    func deleteCredential(forAccountID accountID: UUID)

    /// Rewrites stored credentials so they carry the current iCloud sync
    /// setting. Whether a Keychain item syncs is decided when it is written, so
    /// enabling sync later would otherwise leave existing logins local — and
    /// every other device with an account whose credential never arrives.
    func resyncCredentialsWithCurrentSetting()

    /// The login identifier the user typed. Kept in the Keychain beside the
    /// credential so it never enters synced metadata.
    func setUsername(_ username: String, for account: Account)
    func username(for account: Account) -> String?

    func isLoggedIn(for account: Account) -> Bool
    func refreshLoginStatus(for account: Account)

    // MARK: - Legacy adoption

    /// Whether a pre-revamp credential for this account's instance exists on
    /// this device and has not been adopted by the current identity.
    ///
    /// True only for the account the instance's legacy login was migrated into
    /// — the old item is keyed by instance, and a second login the user added
    /// themselves must never inherit it.
    func hasAdoptableLegacyCredential(for account: Account) -> Bool

    /// Copies the legacy item into this account's scoped key. Returns whether
    /// the copy verified.
    ///
    /// Runs by itself as part of recomputing account status: the upgrade is not
    /// a decision to put to the user. A retained Keychain item carries no proof
    /// of which Apple account it belonged to (measured — see
    /// ``CredentialIdentityScope``), but the pre-revamp release read that item
    /// with `kSecAttrSynchronizableAny` and no identity in its key, so it was
    /// already being served to whoever held the device. The copy is written
    /// device-local so this migration cannot put a secret of unproven
    /// provenance into the current identity's iCloud Keychain.
    @discardableResult
    func adoptLegacyCredential(for account: Account) -> Bool

    /// Deletes the unscoped legacy item **only** if this identity adopted it
    /// and it still holds the adopted secret. Called when an account is really
    /// deleted, never on mere absence.
    func deleteLegacyCredentialIfOwned(for account: Account)
}
