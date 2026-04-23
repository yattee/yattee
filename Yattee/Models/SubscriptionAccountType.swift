//
//  SubscriptionAccountType.swift
//  Yattee
//
//  Subscription account type and configuration for managing channel subscriptions.
//

import Foundation

/// The type of account used for managing subscriptions.
enum SubscriptionAccountType: String, Codable, Sendable, Equatable, CaseIterable {
    /// Local subscriptions synced via iCloud (requires Yattee Server for feed).
    case local
    
    /// Subscriptions managed by an Invidious instance account.
    case invidious
    
    /// Subscriptions managed by a Piped instance account.
    case piped
    
    /// Display name for the account type.
    var displayName: String {
        switch self {
        case .local:
            return String(localized: "subscriptions.account.local")
        case .invidious:
            return String(localized: "subscriptions.account.invidious")
        case .piped:
            return String(localized: "subscriptions.account.piped")
        }
    }
}

/// Represents a configured subscription account.
/// Combines the account type with an optional instance identifier.
struct SubscriptionAccount: Codable, Sendable, Equatable, Hashable {
    /// The type of subscription account.
    let type: SubscriptionAccountType
    
    /// The instance UUID for instance-based accounts (Invidious/Piped).
    /// Nil for local accounts.
    let instanceID: UUID?
    
    /// Local subscription account (iCloud-synced, requires Yattee Server).
    static let local = SubscriptionAccount(type: .local, instanceID: nil)
    
    /// Creates an Invidious subscription account for the given instance.
    /// - Parameter instanceID: The UUID of the Invidious instance.
    /// - Returns: A subscription account configured for Invidious.
    static func invidious(_ instanceID: UUID) -> SubscriptionAccount {
        SubscriptionAccount(type: .invidious, instanceID: instanceID)
    }
    
    /// Creates a Piped subscription account for the given instance.
    /// - Parameter instanceID: The UUID of the Piped instance.
    /// - Returns: A subscription account configured for Piped.
    static func piped(_ instanceID: UUID) -> SubscriptionAccount {
        SubscriptionAccount(type: .piped, instanceID: instanceID)
    }
    
    /// Whether this account requires an authenticated instance.
    var requiresAuthentication: Bool {
        switch type {
        case .local:
            return false
        case .invidious, .piped:
            return true
        }
    }
    
    /// Whether this account requires Yattee Server for feed fetching.
    var requiresYatteeServer: Bool {
        switch type {
        case .local:
            return true
        case .invidious, .piped:
            return false
        }
    }
}
