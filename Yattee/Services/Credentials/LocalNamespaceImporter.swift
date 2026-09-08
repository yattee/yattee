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

        for account in snapshot.accounts {
            switch accountsManager.adoptImportedAccount(account) {
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

            case .imported, .mergedIntoExisting:
                // Per-item atomicity: the local record is only dropped once its
                // credential is verifiably no longer owed by the local scope. A
                // failure leaves the record in *both* namespaces until the next
                // sweep — safe, because the collision rule then reads it as an
                // account the identity already holds and only fills in what is
                // missing.
                // Every store is asked even after one fails: they hold separate
                // Keychain services, and whichever can complete its move should,
                // rather than waiting on a retry it has nothing to do with.
                var moved = true
                for store in credentialStores(account) {
                    let storeMoved = store.migrateCredential(forAccountID: account.id, fromScope: local)
                    moved = moved && storeMoved
                }

                if moved {
                    pruneable.insert(account.id)
                } else {
                    LoggingService.shared.warning(
                        "An imported account's credential could not be moved — leaving it for the next sweep",
                        category: .keychain,
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
