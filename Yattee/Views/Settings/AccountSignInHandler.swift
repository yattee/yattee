//
//  AccountSignInHandler.swift
//  Yattee
//
//  What happens after a login succeeds, for every screen that offers one.
//

import Foundation

/// Files a successful login against an account, creating one if this was a
/// fresh sign-in.
///
/// One implementation for every place a login can be started — the per-instance
/// accounts section, the accounts screen, and adding a source — because the
/// order it does things in is what keeps a half-written login from looking like
/// a real one, and that order is not something a second copy would preserve.
@MainActor
struct AccountSignInHandler {
    let appEnvironment: AppEnvironment
    /// The instance being signed in to. A new account is created on it; an
    /// existing one is expected to already live there.
    let instance: Instance

    /// The identifier is stored beside the credential in the Keychain rather
    /// than on the account record, so it never travels as synced metadata.
    /// - Returns: whether the credential was stored. A login the server
    ///   accepted is not the same as one this device could keep.
    @discardableResult
    func storeLogin(credential: String, username: String, target: AccountLoginTarget) -> Bool {
        // Credential storage refuses to write under an unresolved identity
        // scope, so creating the account first would leave one with no
        // credential — and in a namespace that is discarded the moment the real
        // scope arrives. Fail visibly instead.
        guard appEnvironment.credentialIdentityScope.isResolved else {
            appEnvironment.toastManager.showError(
                String(localized: "accounts.signIn.identityUnresolved")
            )
            return false
        }

        // Re-resolved rather than trusted: signing in takes a round trip, and
        // the account can be deleted on another device while it is happening.
        // Writing the credential then would file a secret under an account that
        // no longer exists, and report success for it.
        if let existing = target.account, appEnvironment.accountsManager.account(id: existing.id) == nil {
            appEnvironment.toastManager.showError(
                String(localized: "accounts.signIn.storeFailed")
            )
            return false
        }

        let account = target.account
            ?? appEnvironment.accountsManager.addAccount(instanceID: instance.id)

        guard let credentials = appEnvironment.accountCredentialsManager(for: account) else {
            // Its instance may have gone in the meantime, which is what makes
            // the backend unresolvable. A provisional account created moments
            // ago must not be left behind.
            if target.account == nil {
                appEnvironment.accountsManager.rollbackAccountCreation(account.id)
            }
            return false
        }

        credentials.setCredential(credential, for: account)

        // Confirm the write landed before reporting success: a Keychain failure
        // would otherwise leave an account that looks signed in but has nothing
        // behind it.
        guard credentials.credential(for: account) != nil else {
            if target.account == nil {
                // Rolled back, not deleted: creating it also queued the marker
                // that stops other devices synthesizing an account for this
                // instance's pre-revamp login, and a sign-in that never
                // completed must not leave that behind.
                appEnvironment.accountsManager.rollbackAccountCreation(account.id)
            }
            appEnvironment.toastManager.showError(
                String(localized: "accounts.signIn.storeFailed")
            )
            return false
        }
        if !username.isEmpty {
            credentials.setUsername(username, for: account)
        }

        appEnvironment.accountsManager.setStatus(.signedIn, for: account.id)

        // `usesAccountLogin` is deliberately not set. It is pre-revamp state
        // that migration only reads, and it syncs through iCloud key-value
        // storage independently of the account records — a device receiving the
        // flag before the account would synthesize a migrated account for a
        // login that was never legacy, and the marker that arrives later does
        // not retract it. Accounts describe logins now; the flag only describes
        // the world before they existed.

        // Signing in again keeps the same account, so nothing downstream sees a
        // change of context — but the credential behind it may now belong to
        // somebody else, and their data must not survive the swap.
        appEnvironment.accountCredentialDidChange(for: account)

        return true
    }
}
