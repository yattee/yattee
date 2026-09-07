//
//  SourceRow.swift
//  Yattee
//
//  Unified row view for displaying any source type in the sources list.
//

import SwiftUI

struct SourceRow: View {
    let source: UnifiedSource
    let onEdit: () -> Void

    @Environment(\.appEnvironment) private var appEnvironment

    /// Computed property that checks password status reactively for WebDAV sources
    private var needsPassword: Bool {
        guard case .fileSource(let mediaSource) = source,
              mediaSource.type == .webdav else { return false }
        return appEnvironment?.mediaSourcesManager.needsPassword(for: mediaSource) ?? false
    }

    /// Computed property that checks instance status for auth issues
    private var instanceStatus: InstanceStatus? {
        guard case .remoteServer(let instance) = source else { return nil }
        return appEnvironment?.instancesManager.status(for: instance)
    }

    /// Whether this instance has auth issues (failed or required)
    private var hasAuthIssue: Bool {
        guard let status = instanceStatus else { return false }
        return status == .authFailed || status == .authRequired
    }

    /// Whether a remote server instance requires credentials that are missing from
    /// the Keychain (e.g. after reinstalling and importing sources from iCloud).
    private var needsCredentials: Bool {
        guard case .remoteServer(let instance) = source else { return false }
        return appEnvironment?.needsCredentials(for: instance) ?? false
    }

    /// Whether one of this source's logins is being refused by the server.
    ///
    /// The instance-level statuses know nothing about accounts, so a rejected
    /// login would otherwise show up nowhere the user looks for their sources.
    private var hasRejectedAccount: Bool {
        guard case .remoteServer(let instance) = source,
              let accountsManager = appEnvironment?.accountsManager else { return false }

        return accountsManager.accounts(forInstance: instance.id).contains {
            accountsManager.status(for: $0.id) == .credentialRejected
        }
    }

    var body: some View {
        #if os(tvOS)
        Button(action: onEdit) {
            rowContent
        }
        .buttonStyle(.card)
        .accessibilityIdentifier(accessibilityId)
        #else
        rowContent
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(accessibilityId)
        #endif
    }

    private var rowContent: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(source.name)
                        .font(.headline)

                    if !source.isEnabled {
                        Text(String(localized: "sources.status.disabled"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }

                Text(source.urlDisplayString)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                statusView
            }

            Spacer()
        }
    }

    /// Generates a unique accessibility identifier for the source row.
    /// Format: sources.row.<type>.<host>
    private var accessibilityId: String {
        switch source {
        case .remoteServer(let instance):
            let host = instance.url.host ?? "unknown"
            return "sources.row.\(instance.type.rawValue).\(host)"
        case .fileSource(let mediaSource):
            let identifier = mediaSource.url.host ?? mediaSource.name.replacingOccurrences(of: " ", with: "_")
            return "sources.row.\(mediaSource.type.rawValue).\(identifier)"
        }
    }

    @ViewBuilder
    private var statusView: some View {
        // A refused login comes first: it names one thing the user has to do,
        // and two warnings stacked on one row say less than either alone.
        if hasRejectedAccount {
            Label(
                AccountStatusBadge.text(for: .credentialRejected),
                systemImage: "person.crop.circle.badge.exclamationmark"
            )
            .font(.caption2)
            .foregroundStyle(AccountStatusBadge.color(for: .credentialRejected))
        } else if needsPassword || needsCredentials {
            Label(String(localized: "sources.status.authRequired"), systemImage: "key.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        } else if hasAuthIssue {
            // Show auth issue for remote servers (Yattee Server auth failed)
            if instanceStatus == .authFailed {
                Label(String(localized: "sources.status.authFailed"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Label(String(localized: "sources.status.authRequired"), systemImage: "key.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        SourceRow(
            source: .remoteServer(Instance(type: .invidious, url: URL(string: "https://invidious.example.com")!)),
            onEdit: {}
        )
        SourceRow(
            source: .fileSource(.webdav(name: "My NAS", url: URL(string: "https://nas.local:5006")!)),
            onEdit: {}
        )
        SourceRow(
            source: .fileSource(.localFolder(name: "Movies", url: URL(fileURLWithPath: "/Users/user/Movies"))),
            onEdit: {}
        )
    }
    .appEnvironment(.preview)
}
