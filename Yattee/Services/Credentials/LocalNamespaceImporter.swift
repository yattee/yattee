//
//  LocalNamespaceImporter.swift
//  Yattee
//
//  Hands accounts created while signed out of iCloud to the identity that
//  signs in.
//

import Foundation

/// Imports the `local` account namespace into whichever identity is active.
///
/// Accounts added while no Apple account was available are stored under
/// `accounts.local.*`, with their credentials keyed `local|<accountID>`. When an
/// identity resolves, everything namespaced by it is reloaded — and without this
/// the local data would simply stop being read, permanently.
///
/// A repeatable sweep rather than a one-shot migration, for two reasons. Signing
/// out refills the local namespace, so the same work is owed again on the next
/// sign-in; and any part of it that cannot be completed — a credential the
/// Keychain refuses to copy — has to be retried rather than lost. Every step is
/// therefore idempotent, and per item: an account is removed from the local
/// namespace only once both its record and its secret have been dealt with.
///
/// Runs entirely synchronously on the main actor. The fences below are checked
/// once, at entry, and nothing awaits afterwards — so an identity change cannot
/// interleave with a sweep in progress.
@MainActor
final class LocalNamespaceImporter {
    private let accountsManager: AccountsManager
    private let identityScope: CredentialIdentityScope

    /// The credential stores that could be holding an account's secret.
    ///
    /// Usually the one its instance's type names. An account whose instance has
    /// not synced yet resolves to none, so every account-keyed store is asked
    /// instead — at most one of them holds anything, and the alternative is
    /// stranding a credential under a namespace nothing will ever read again.
    private let credentialStores: @MainActor (Account) -> [any AccountCredentialsManager]

    init(
        accountsManager: AccountsManager,
        identityScope: CredentialIdentityScope,
        credentialStores: @escaping @MainActor (Account) -> [any AccountCredentialsManager]
    ) {
        self.accountsManager = accountsManager
        self.identityScope = identityScope
        self.credentialStores = credentialStores
    }

    /// Moves whatever the signed-out namespace still holds into the active
    /// identity.
    ///
    /// - Returns: whether anything was taken over, so the caller can recompute
    ///   what it derives from accounts and credentials.
    @discardableResult
    func sweepIfNeeded() -> Bool {
        let local = CredentialIdentityScope.localScope

        // Decisions 9 and 10: an install with no Apple account — signed out, or
        // sideloaded with no iCloud entitlement — is permanently scoped `local`
        // and has nothing to import into, and the `unresolved` holding pen is
        // never a destination either.
        guard let scope = identityScope.current, scope != local else { return false }

        // The same fence `save()` uses. The scope moves the instant the identity
        // does, while the reload that refills memory runs on a main-queue
        // observer afterwards; sweeping in that window would merge the local
        // namespace into a manager still describing the previous identity.
        guard accountsManager.loadedNamespace == scope else {
            LoggingService.shared.info(
                "Skipping the local-namespace import — the account namespace is still reloading",
                category: .general,
                details: "loaded=\(accountsManager.loadedNamespace), current=\(scope)"
            )
            return false
        }

        let snapshot = accountsManager.localNamespaceSnapshot()
        guard snapshot.hasContent else { return false }

        var pruneable: Set<UUID> = []
        var refused: Set<UUID> = []

        // The credential is settled before the record is adopted, never the
        // other way round, and both are needed twice over.
        //
        // Adopting announces: `.accountsDidChange` brings the status refresh —
        // and the silent legacy adoption it can reach — down on the account
        // synchronously, before this loop gets to its secret. That observer
        // would find the identity's key empty and fill it with the pre-revamp
        // unscoped item, an older secret of unproven provenance; the move that
        // follows would then read its own target as occupied and delete the
        // valid login as redundant. Nothing is announced here until there is
        // nothing left to move.
        //
        // And a record adopted beside a credential that would not follow leaves
        // the account owned by two namespaces at once. Signing into a second
        // identity before the retry claims it there as well, and no later sweep
        // can take it back out of the first — an account permanently in two
        // Apple accounts. Settling first means a failure leaves *nothing* under
        // the identity, so whoever signs in next simply imports it cleanly.
        //
        // Residual, and the reason this order rather than a transaction: a
        // process death between the credential settling and the record being
        // adopted strands the secret under the identity that was active. The
        // record is still local, so it lands wherever the user signs in next and
        // reads as sign-in-required there. Inconvenient, and recoverable by
        // signing in again — never a silent corruption, which is what the other
        // order risks.
        for account in snapshot.accounts {
            switch accountsManager.importEligibility(for: account) {
            case .rejectedByTombstone:
                // Decision 5: the account was deliberately deleted under this
                // identity, so the local copy is not resurrected — and its
                // secret goes with it rather than outliving the record.
                //
                // Held to the same per-item atomicity as an import: the local
                // record is the only thing that names the secret being deleted,
                // so pruning it over a Keychain failure would orphan that
                // secret permanently. Left in place, the next sweep refuses the
                // account again and retries the deletion.
                refused.insert(account.id)

                var deleted = true
                for store in credentialStores(account) {
                    let storeDeleted = store.deleteCredential(forAccountID: account.id, inScope: local)
                    deleted = deleted && storeDeleted
                }

                if deleted {
                    pruneable.insert(account.id)
                } else {
                    LoggingService.shared.warning(
                        "A refused account's credential could not be deleted — leaving it for the next sweep",
                        category: .keychain,
                        details: "accountID=\(account.id)"
                    )
                }

            case .adoptable:
                // Per-item atomicity: the local record is only dropped once its
                // credential is verifiably no longer owed by the local scope,
                // and it is only handed to the identity once the same is true.
                // A failure leaves both where they are for the next sweep.
                // Every store is asked even after one fails: they hold separate
                // Keychain services, and whichever can complete its move should,
                // rather than waiting on a retry it has nothing to do with.
                var moved = true
                for store in credentialStores(account) {
                    let storeMoved = store.migrateCredential(forAccountID: account.id, fromScope: local)
                    moved = moved && storeMoved
                }

                guard moved else {
                    LoggingService.shared.warning(
                        "An account's credential could not be moved — leaving the record where it is",
                        category: .keychain,
                        details: "accountID=\(account.id)"
                    )
                    continue
                }

                switch accountsManager.adoptImportedAccount(account) {
                case .imported, .mergedIntoExisting:
                    pruneable.insert(account.id)

                case .rejectedByTombstone, .deferred:
                    // Neither is reachable: both answers come from the state
                    // this loop read a moment ago, and nothing between the two
                    // calls awaits or gives anything else a turn to change it.
                    // Left local all the same — a next sweep re-reads the fate
                    // and finishes the job whichever way it now reads.
                    LoggingService.shared.warning(
                        "An account's fate changed mid-import — leaving the record where it is",
                        category: .general,
                        details: "accountID=\(account.id)"
                    )
                }

            case .deferred:
                // Only reachable if the namespace moved under a sweep, which
                // nothing here awaits long enough to allow. Nothing is pruned.
                LoggingService.shared.warning(
                    "The account namespace moved during an import — leaving the record where it is",
                    category: .general,
                    details: "accountID=\(account.id)"
                )
            }
        }

        // Decision 4: the markers are copied, never moved.
        accountsManager.adoptImportedMigratedInstances(snapshot.migratedInstanceIDs)

        var contextHandled = false
        if let carried = snapshot.storedContext {
            // Handled either way: adopted when this identity has never chosen a
            // context, dropped when it has. The local keys are cleared in both
            // cases, or every activation would offer the same stale selection.
            contextHandled = true

            var context = carried.context
            // Decision 6: never carry a selection naming an account that was
            // just refused — or one that exists in neither namespace. The user's
            // own data is the only thing left to point at.
            if let accountID = context.accountID,
               refused.contains(accountID) || accountsManager.account(id: accountID) == nil {
                context = .local
            }

            accountsManager.adoptImportedContext(
                StoredDataContext(context: context, changedAt: carried.changedAt)
            )
        }

        accountsManager.pruneLocalNamespace(
            removingAccountIDs: pruneable,
            clearContext: contextHandled
        )

        let didChange = !pruneable.isEmpty || contextHandled
        if didChange {
            LoggingService.shared.info(
                "Imported the signed-out account namespace into the active identity",
                category: .general,
                details: "imported=\(pruneable.subtracting(refused).count), refused=\(refused.count)"
            )
        }
        return didChange
    }
}
