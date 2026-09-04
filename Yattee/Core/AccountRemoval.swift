//
//  AccountRemoval.swift
//  Yattee
//
//  Taking an account off this device by hand.
//

import Foundation

/// The removal cascade for an account whose instance is gone.
///
/// Kept out of `AppEnvironment` so the ordering can be exercised directly: an
/// orphan is exactly the case where the usual lookups return nothing, and a
/// cascade that quietly skips a step leaves a secret behind with no screen left
/// to reach it from.
@MainActor
enum AccountRemoval {
    /// Removes an orphaned account and the credential filed under its ID.
    ///
    /// `AppEnvironment.accountCredentialsManager(for:)` resolves the store from
    /// the account's instance, and an orphan has none — going through it would
    /// return `nil` and delete nothing. Every account-keyed store is asked to
    /// drop the ID instead; at most one of them holds anything, and the scoped
    /// key needs only the ID. The unscoped legacy item is deliberately left
    /// alone: identifying it needs the instance, which is precisely what is
    /// missing.
    static func removeOrphan(
        _ accountID: UUID,
        stores: [any AccountCredentialsManager],
        accountsManager: AccountsManager,
        discardData: (UUID) -> Void
    ) {
        for store in stores {
            store.deleteCredential(forAccountID: accountID)
        }

        accountsManager.removeAccount(accountID)
        // Whatever the account had in memory goes with it, or its subscriptions
        // and playlists would keep answering for an account nobody has.
        discardData(accountID)
    }
}
