//
//  VideoListContent.swift
//  Yattee
//
//  Handles inset/plain list styling without ScrollView wrapper.
//

import SwiftUI

/// A container that applies inset card or plain styling to list content.
///
/// Unlike `VideoListContainer`, this component does NOT wrap content in a ScrollView.
/// Use this when the parent view already has its own ScrollView with additional content
/// (tabs, headers, etc.).
///
/// Usage:
/// ```swift
/// ScrollView {
///     VStack(spacing: 0) {
///         tabPicker
///         
///         VideoListContent(listStyle: listStyle) {
///             ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
///                 VideoListRow(
///                     isLast: index == videos.count - 1,
///                     rowStyle: rowStyle,
///                     listStyle: listStyle
///                 ) {
///                     VideoRowView(video: video, style: rowStyle)
///                 }
///             }
///         }
///     }
/// }
/// ```
struct VideoListContent<Content: View>: View {
    let listStyle: VideoListStyle

    @ViewBuilder let content: () -> Content

    /// Corner radius for card container in inset style.
    private let cardCornerRadius: CGFloat = 10

    /// Horizontal padding for card container.
    private let cardHorizontalPadding: CGFloat = 16

    /// Bottom padding for content.
    private let bottomPadding: CGFloat = 16

    var body: some View {
        let list = LazyVStack(spacing: 0) {
            content()
        }

        if listStyle == .inset {
            list
                #if !os(tvOS)
                .background(ListBackgroundStyle.card.color)
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
                #endif
                .padding(.horizontal, cardHorizontalPadding)
                .padding(.bottom, bottomPadding)
        } else {
            list
                .padding(.bottom, bottomPadding)
        }
    }
}

// MARK: - Preview

#Preview("Inset Style") {
    ScrollView {
        VideoListContent(listStyle: .inset) {
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
    }
    #if os(iOS)
    .background(Color(uiColor: .systemGroupedBackground))
    #endif
}

#Preview("Plain Style") {
    ScrollView {
        VideoListContent(listStyle: .plain) {
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
