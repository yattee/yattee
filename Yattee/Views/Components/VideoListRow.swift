//
//  VideoListRow.swift
//  Yattee
//
//  Row wrapper that applies consistent padding and divider logic.
//

import SwiftUI

/// A wrapper for list row content that applies consistent padding and dividers.
///
/// Handles:
/// - Row padding (16 horizontal, 12 vertical)
/// - Divider visibility (hidden for last item)
/// - Divider leading padding (aligned to content after thumbnail/avatar)
///
/// Usage:
/// ```swift
/// // For video rows (uses thumbnailWidth for divider alignment)
/// ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
///     VideoListRow(
///         isLast: index == videos.count - 1,
///         rowStyle: rowStyle,
///         listStyle: listStyle
///     ) {
///         VideoRowView(video: video, style: rowStyle)
///             .tappableVideo(video)
///     }
/// }
///
/// // For channel rows (uses thumbnailHeight for circular avatar alignment)
/// ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
///     VideoListRow(
///         isLast: index == channels.count - 1,
///         rowStyle: rowStyle,
///         listStyle: listStyle,
///         contentWidth: rowStyle.thumbnailHeight  // Avatar is square
///     ) {
///         ChannelRowView(channel: channel, style: rowStyle)
///     }
/// }
/// ```
struct VideoListRow<Content: View>: View {
    let isLast: Bool
    let rowStyle: VideoRowStyle
    let listStyle: VideoListStyle

    /// Optional override for content width used in divider alignment.
    /// If nil, uses `rowStyle.thumbnailWidth`.
    /// For channel rows with circular avatars, pass `rowStyle.thumbnailHeight`.
    var contentWidth: CGFloat?

    /// Optional index column width for playlist rows.
    /// When set, adds this width plus spacing before the thumbnail width.
    var indexWidth: CGFloat?

    @ViewBuilder let content: () -> Content

    /// Horizontal padding for row content.
    private let horizontalPadding: CGFloat = 16

    /// Vertical padding for row content.
    private let verticalPadding: CGFloat = 12

    /// Spacing between thumbnail/avatar and text.
    private let thumbnailTextSpacing: CGFloat = 12

    /// Calculated divider leading padding (aligns with text after thumbnail/avatar).
    private var dividerLeadingPadding: CGFloat {
        let width = contentWidth ?? rowStyle.thumbnailWidth
        let indexOffset = indexWidth.map { $0 + thumbnailTextSpacing } ?? 0
        return horizontalPadding + indexOffset + width + thumbnailTextSpacing
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
        #elseif !os(tvOS)
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
                VideoListRow(
                    isLast: index == 4,
                    rowStyle: .regular,
                    listStyle: .inset
                ) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 120, height: 68)
                        VStack(alignment: .leading) {
                            Text(verbatim: "Video Title \(index + 1)")
                                .font(.subheadline)
                            Text(verbatim: "Channel Name")
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
                VideoListRow(
                    isLast: index == 4,
                    rowStyle: .regular,
                    listStyle: .plain
                ) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 120, height: 68)
                        VStack(alignment: .leading) {
                            Text(verbatim: "Video Title \(index + 1)")
                                .font(.subheadline)
                            Text(verbatim: "Channel Name")
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
