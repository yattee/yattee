//
//  DataContext.swift
//  Yattee
//
//  Which data set the Subscriptions, Feed and Playlists views are showing.
//

import Foundation

/// The globally selected source of user data.
///
/// Replaces `SubscriptionAccount`, which could only ever describe *subscriptions*
/// and identified an account by the instance it lived on — a model that cannot
/// express two logins on the same instance.
enum DataContext: Codable, Hashable, Sendable {
    /// The device's own data, synced through iCloud.
    case local
    /// A specific `Account.id`.
    case account(UUID)

    var accountID: UUID? {
        if case let .account(id) = self { return id }
        return nil
    }

    var isLocal: Bool { self == .local }
}

/// A context together with the moment it was chosen.
///
/// The timestamp is app-managed and is the only ordering used when two devices
/// pick different contexts — CloudKit's own modification dates are never
/// consulted, because they record when a *record* was written rather than when
/// the user made a choice.
struct StoredDataContext: Codable, Hashable, Sendable {
    var context: DataContext
    var changedAt: Date

    init(context: DataContext, changedAt: Date = Date()) {
        self.context = context
        self.changedAt = changedAt
    }

    /// A context produced by migrating the legacy `subscriptionAccount` value.
    ///
    /// Stamped at the epoch so that any explicit choice the user has made on any
    /// device outranks it regardless of which arrives first. A migration is a
    /// guess at intent; an explicit choice is intent.
    static func migrated(_ context: DataContext) -> StoredDataContext {
        StoredDataContext(context: context, changedAt: Date(timeIntervalSince1970: 0))
    }

    var isMigrated: Bool { changedAt == Date(timeIntervalSince1970: 0) }
}

// MARK: - Legacy migration

extension DataContext {
    /// Maps the pre-revamp `SubscriptionAccount` onto a context.
    ///
    /// The instance UUID becomes the account UUID directly: migrated accounts
    /// deliberately reuse their instance's UUID (see `Account.migrated(from:)`),
    /// so this is an identity mapping rather than a lookup that could fail.
    init(legacy: SubscriptionAccount) {
        switch legacy.type {
        case .local:
            self = .local
        case .invidious, .piped:
            if let instanceID = legacy.instanceID {
                self = .account(instanceID)
            } else {
                self = .local
            }
        }
    }
}
