//
//  MigrationImportRow.swift
//  Yattee
//
//  Reusable row component for displaying a legacy import item.
//

import SwiftUI

struct MigrationImportRow: View {
    let item: LegacyImportItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Checkbox
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isSelected ? Color.accentColor : .secondary)

                // Instance type icon
                instanceIcon
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                // Instance details
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Text(item.url.host ?? item.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Reachability indicator
                reachabilityIndicator
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var instanceIcon: some View {
        switch item.instanceType {
        case .invidious:
            Image(systemName: "server.rack")
        case .piped:
            Image(systemName: "cloud")
        default:
            Image(systemName: "globe")
        }
    }

    @ViewBuilder
    private var reachabilityIndicator: some View {
        switch item.reachabilityStatus {
        case .unknown:
            EmptyView()
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .reachable:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .unreachable:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        MigrationImportRow(
            item: LegacyImportItem(
                id: UUID(),
                legacyInstanceID: "test",
                instanceType: .invidious,
                url: URL(string: "https://invidious.example.com")!,
                name: "My Invidious",
                isSelected: true,
                reachabilityStatus: .reachable
            ),
            onToggle: {}
        )

        MigrationImportRow(
            item: LegacyImportItem(
                id: UUID(),
                legacyInstanceID: "test2",
                instanceType: .piped,
                url: URL(string: "https://piped.example.com")!,
                name: nil,
                isSelected: false,
                reachabilityStatus: .unreachable
            ),
            onToggle: {}
        )

        MigrationImportRow(
            item: LegacyImportItem(
                id: UUID(),
                legacyInstanceID: "test3",
                instanceType: .invidious,
                url: URL(string: "https://another.invidious.com")!,
                name: "Another Instance",
                isSelected: true,
                reachabilityStatus: .checking
            ),
            onToggle: {}
        )
    }
}
