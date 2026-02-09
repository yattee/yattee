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
        if needsPassword {
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
