//
//  VideoGridContent.swift
//  Yattee
//
//  Reusable grid content wrapper for video card layouts.
//

import SwiftUI

/// A wrapper that provides standard LazyVGrid configuration for video cards.
///
/// This component eliminates duplicate LazyVGrid boilerplate across grid-enabled views.
/// It handles the grid columns, spacing, and padding consistently.
///
/// Use this when the parent view already has its own ScrollView (e.g., views with
/// tabs, headers, or other content above/below the grid).
///
/// Usage:
/// ```swift
/// ScrollView {
///     // Optional header content
///     tabBar
///
///     VideoGridContent(columns: gridConfig.effectiveColumns) {
///         ForEach(videos) { video in
///             VideoCardView(video: video, isCompact: gridConfig.isCompactCards)
///                 .tappableVideo(video)
///         }
///     }
/// }
/// ```
struct VideoGridContent<Content: View>: View {
    let columns: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(
            columns: makeGridColumns(count: columns),
            spacing: GridConstants.spacing
        ) {
            content()
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
    }
}

// MARK: - Preview

#Preview("Video Grid") {
    ScrollView {
        VideoGridContent(columns: 3) {
            ForEach(0..<9) { index in
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay {
                        Text("Card \(index + 1)")
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }
}
