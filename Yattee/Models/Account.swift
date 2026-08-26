//
//  Account.swift
//  Yattee
//
//  A single sign-in on a backend instance. One instance may hold several.
//

import Foundation

/// A user's login on an instance.
///
/// Yattee 2 collapsed v1's multi-account model into "one instance = at most one
/// credential" (`Instance.usesAccountLogin` plus a Keychain item keyed by the
/// instance's UUID). `Account` restores multi-login: the instance describes the
/// *server*, the account describes *who is signed in to it*.
///
/// The login identifier (username/email) is deliberately **not** stored here —
/// it lives in the Keychain beside the credential, so synced metadata never
/// carries account identifiers. Only `displayName` is a synced label.
///
/// `type` is not stored either: it is derived by resolving `instanceID` through
/// `InstancesManager`, so an instance that changes type can never disagree with
/// its accounts.
struct Account: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let instanceID: UUID

    /// User-set label. The only name that syncs.
    var displayName: String?

    let dateAdded: Date

    /// Bumped on every user edit — supplies the ordering for conflict
    /// resolution, which never relies on CloudKit modification dates.
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        instanceID: UUID,
        displayName: String? = nil,
        dateAdded: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.instanceID = instanceID
        self.displayName = displayName
        self.dateAdded = dateAdded
        self.updatedAt = updatedAt
    }

    /// The account synthesized for an instance that was signed in before
    /// multi-account support existed.
    ///
    /// The account's `id` is deliberately the **instance's** UUID: at most one
    /// credential ever existed per instance, so reusing the UUID makes the
    /// migration deterministic across devices — two devices migrating
    /// independently produce the identical record name, which merges per-record
    /// instead of duplicating.
    static func migrated(from instanceID: UUID, dateAdded: Date = Date()) -> Account {
        Account(
            id: instanceID,
            instanceID: instanceID,
            displayName: nil,
            dateAdded: dateAdded,
            // Epoch-old: any explicit user edit on any device outranks a
            // migration write regardless of arrival order.
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// Whether this account was produced by the legacy migration rather than an
    /// explicit sign-in.
    var isMigrated: Bool { id == instanceID }

    /// Whether `other` should replace this copy.
    ///
    /// Ordered by the app-managed `updatedAt`, with the label settling an exact
    /// tie. The tie is reachable — two devices can migrate the same account in
    /// the same instant, and every migrated account is stamped at the epoch — and
    /// without a tie-break each device would keep its own label and consider the
    /// matter closed, which is a divergence neither would ever notice.
    func isOutranked(by other: Account) -> Bool {
        if other.updatedAt != updatedAt { return other.updatedAt > updatedAt }
        return (other.displayName ?? "") > (displayName ?? "")
    }
}
