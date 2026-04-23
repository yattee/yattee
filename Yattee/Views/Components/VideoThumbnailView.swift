//
//  VideoThumbnailView.swift
//  Yattee
//
//  Reusable video thumbnail component with consistent 16:9 aspect ratio and optional overlays.
//

import SwiftUI
import NukeUI

/// A reusable video thumbnail view with 16:9 aspect ratio.
///
/// Supports optional overlays for:
/// - Watch progress bar
/// - Duration badge
/// - Download status (completed checkmark or progress indicator)
/// - Live badge
struct VideoThumbnailView: View {
    let url: URL?

    var cornerRadius: CGFloat = 8
    var watchProgress: Double? = nil
    var duration: String? = nil
    var durationAlignment: Alignment = .bottomLeading
    var isDownloaded: Bool = false
    var downloadProgress: Double? = nil
    /// When true, shows a spinner instead of progress arc (for unknown file sizes)
    var downloadProgressIndeterminate: Bool = false
    var isLive: Bool = false
    var placeholderTitle: String? = nil
    var isWatched: Bool = false

    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        if let title = placeholderTitle {
                            Text(title)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .padding(8)
                        }
                    }
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .overlay(alignment: .bottom) {
            watchProgressBar
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(alignment: durationAlignment) {
            durationBadge
        }
        .overlay(alignment: .bottomTrailing) {
            downloadIndicator
        }
        .overlay(alignment: .topTrailing) {
            liveBadge
        }
        .overlay(alignment: .topLeading) {
            watchedCheckmark
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var watchProgressBar: some View {
        if let progress = watchProgress, progress > 0 && progress < 1 {
            GeometryReader { geo in
                Rectangle()
                    .fill(.red)
                    .frame(width: geo.size.width * progress, height: 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
    }

    @ViewBuilder
    private var durationBadge: some View {
        if let duration, !duration.isEmpty {
            DurationBadge(text: duration)
                .padding(cornerRadius > 6 ? 6 : 4)
        }
    }

    @ViewBuilder
    private var downloadIndicator: some View {
        if isDownloaded {
            Image(systemName: "arrow.down.circle")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.8))
                .clipShape(Circle())
                .padding(4)
        } else if let progress = downloadProgress, progress < 1 || downloadProgressIndeterminate {
            DownloadProgressIndicator(
                progress: progress,
                size: cornerRadius > 6 ? 28 : 22,
                isIndeterminate: downloadProgressIndeterminate
            )
            .padding(4)
        }
    }

    @ViewBuilder
    private var liveBadge: some View {
        if isLive {
            Text(String(localized: "video.badge.live"))
                .font(.caption2)
                .fontWeight(.bold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.red)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(6)
        }
    }

    @ViewBuilder
    private var watchedCheckmark: some View {
        if isWatched && !isLive {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: cornerRadius > 6 ? 20 : 14))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.background, .tint)
                .padding(cornerRadius > 6 ? 3 : 2)
        }
    }
}

// MARK: - Preview

#Preview("Default") {
    VideoThumbnailView(url: nil)
        .frame(width: 280)
        .padding()
}

#Preview("With Progress") {
    VideoThumbnailView(
        url: nil,
        watchProgress: 0.6,
        duration: "12:34"
    )
    .frame(width: 280)
    .padding()
}

#Preview("Downloaded") {
    VideoThumbnailView(
        url: nil,
        duration: "1:23:45",
        isDownloaded: true
    )
    .frame(width: 280)
    .padding()
}

#Preview("Live") {
    VideoThumbnailView(
        url: nil,
        isLive: true
    )
    .frame(width: 280)
    .padding()
}

#Preview("Watched") {
    VideoThumbnailView(
        url: nil,
        duration: "12:34",
        isWatched: true
    )
    .frame(width: 280)
    .padding()
}
