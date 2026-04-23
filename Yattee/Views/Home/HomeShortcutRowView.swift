//
//  HomeShortcutRowView.swift
//  Yattee
//
//  Row component for home shortcuts in list layout.
//

import SwiftUI

struct HomeShortcutRowView<StatusIndicator: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    var statusIndicator: StatusIndicator?

    init(
        icon: String,
        title: String,
        subtitle: String,
        statusIndicator: StatusIndicator?
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.statusIndicator = statusIndicator
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    if let statusIndicator {
                        statusIndicator
                    }
                }

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Convenience Initializer (no status indicator)

extension HomeShortcutRowView where StatusIndicator == EmptyView {
    init(
        icon: String,
        title: String,
        subtitle: String
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.statusIndicator = nil
    }
}
