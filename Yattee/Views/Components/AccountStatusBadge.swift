//
//  AccountStatusBadge.swift
//  Yattee
//
//  How an account's status reads, wherever accounts are listed.
//

import SwiftUI

/// An account's status as one line of caption text.
///
/// Shared so a status says the same thing in every list it appears in — the
/// per-instance section, the accounts screen and the context switcher all name
/// the same states, and one added to `AccountStatus` is named once rather than
/// three times.
struct AccountStatusBadge: View {
    let status: AccountStatus

    var body: some View {
        Text(Self.text(for: status))
            .font(.caption)
            .foregroundStyle(Self.color(for: status))
    }

    static func text(for status: AccountStatus) -> String {
        switch status {
        case .checking: String(localized: "accounts.status.checking")
        case .signedIn: String(localized: "accounts.status.signedIn")
        case .credentialMissing: String(localized: "accounts.status.credentialMissing")
        case .credentialRejected: String(localized: "accounts.status.credentialRejected")
        case .unreachable: String(localized: "accounts.status.unreachable")
        }
    }

    /// Only the states the user has to act on are coloured. A credential that
    /// never arrived on this device is ordinary — tvOS never receives them at
    /// all — so it reads as secondary rather than as a fault.
    static func color(for status: AccountStatus) -> Color {
        switch status {
        case .checking: .secondary
        case .signedIn: .secondary
        case .credentialMissing: .secondary
        case .credentialRejected: .red
        case .unreachable: .orange
        }
    }
}
