//
//  SourceListRow.swift
//  Yattee
//
//  Row wrapper for source list items with consistent padding and dividers.
//

import SwiftUI

/// A wrapper for source list row content that applies consistent padding and dividers.
///
/// Similar to VideoListRow but with fixed icon width for source rows.
struct SourceListRow<Content: View>: View {
    let isLast: Bool
    let listStyle: VideoListStyle

    @ViewBuilder let content: () -> Content

    /// Horizontal padding for row content.
    private let horizontalPadding: CGFloat = 16

    /// Vertical padding for row content.
    private let verticalPadding: CGFloat = 12

    /// Width of the icon column.
    private let iconWidth: CGFloat = 32

    /// Spacing between icon and text.
    private let iconTextSpacing: CGFloat = 12

    /// Calculated divider leading padding (aligns with text after icon).
    private var dividerLeadingPadding: CGFloat {
        horizontalPadding + iconWidth + iconTextSpacing
    }

    var body: some View {
        VStack(spacing: 0) {
            content()
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)

            if !isLast {
                divider
            }
        }
    }

    // MARK: - Private

    @ViewBuilder
    private var divider: some View {
        #if os(iOS)
        Rectangle()
            .fill(Color(uiColor: .separator))
            .frame(height: 1 / UIScreen.main.scale)
            .padding(.leading, dividerLeadingPadding)
        #elseif os(macOS)
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .padding(.leading, dividerLeadingPadding)
        #else
        Divider()
            .padding(.leading, dividerLeadingPadding)
        #endif
    }
}

// MARK: - Preview

#Preview("Inset Style") {
    ScrollView {
        LazyVStack(spacing: 0) {
            ForEach(0..<5) { index in
                SourceListRow(isLast: index == 4, listStyle: .inset) {
                    HStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 32)
                        VStack(alignment: .leading) {
                            Text("Source \(index + 1)")
                                .font(.headline)
                            Text("example.com")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding()
    }
}

#Preview("Plain Style") {
    ScrollView {
        LazyVStack(spacing: 0) {
            ForEach(0..<5) { index in
                SourceListRow(isLast: index == 4, listStyle: .plain) {
                    HStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 32)
                        VStack(alignment: .leading) {
                            Text("Source \(index + 1)")
                                .font(.headline)
                            Text("example.com")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }
}
