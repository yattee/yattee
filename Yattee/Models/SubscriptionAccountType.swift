//
//  SubscriptionAccountType.swift
//  Yattee
//
//  Pre-revamp subscription account state, kept only so it can be decoded.
//

import Foundation

/// The type of account used for managing subscriptions.
///
/// Legacy: superseded by `DataContext` and `Account`. Nothing writes this type
/// any more — it survives so `AccountsManager.legacySubscriptionAccount()` can
/// read the selection an upgrading install persisted, and
/// `DataContext.init(legacy:)` can map it onto a context. Do not add members.
enum SubscriptionAccountType: String, Codable, Sendable, Equatable, CaseIterable {
    /// Local subscriptions synced via iCloud (requires Yattee Server for feed).
    case local

    /// Subscriptions managed by an Invidious instance account.
    case invidious

    /// Subscriptions managed by a Piped instance account.
    case piped
}

/// A configured subscription account as the previous release persisted it.
/// Decode-only; see `SubscriptionAccountType`.
struct SubscriptionAccount: Codable, Sendable, Equatable, Hashable {
    /// The type of subscription account.
    let type: SubscriptionAccountType

    /// The instance UUID for instance-based accounts (Invidious/Piped).
    /// Nil for local accounts.
    let instanceID: UUID?
}
