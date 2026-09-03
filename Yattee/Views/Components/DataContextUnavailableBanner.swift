//
//  DataContextUnavailableBanner.swift
//  Yattee
//
//  Says why the selected account is not the one answering right now.
//

import SwiftUI

/// A thin strip shown while the selected account context cannot be used.
///
/// Informational only: the selection is deliberately kept — it comes back on
/// its own when the credential or instance arrives — and reads fall back to
/// local data meanwhile, which is exactly what the user would otherwise have to
/// guess at. The switcher sits in the toolbar beside it for anyone who wants to
/// choose something else.
struct DataContextUnavailableBanner: View {
    let reason: DataContextUnavailability

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
    }

    private var icon: String {
        switch reason {
        case .checking: "clock"
        case .instancePending: "clock"
        case .instanceDisabled: "server.rack"
        case .credentialMissing: "person.badge.key"
        case .credentialRejected: "exclamationmark.triangle.fill"
        case .unreachable: "wifi.exclamationmark"
        }
    }

    private var tint: Color {
        switch reason {
        case .checking, .instancePending: .secondary
        case .instanceDisabled: .secondary
        case .credentialMissing: .secondary
        case .credentialRejected: .red
        case .unreachable: .orange
        }
    }

    private var message: String {
        switch reason {
        case .checking: String(localized: "subscriptions.banner.checking")
        case .instancePending: String(localized: "subscriptions.banner.instancePending")
        case .instanceDisabled: String(localized: "subscriptions.banner.instanceDisabled")
        case .credentialMissing: String(localized: "subscriptions.banner.credentialMissing")
        case .credentialRejected: String(localized: "subscriptions.banner.credentialRejected")
        case .unreachable: String(localized: "subscriptions.banner.unreachable")
        }
    }
}
