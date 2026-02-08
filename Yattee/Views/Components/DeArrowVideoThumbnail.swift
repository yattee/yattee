//
//  DeArrowVideoThumbnail.swift
//  Yattee
//
//  Video thumbnail that automatically fetches and displays DeArrow branding.
//

import SwiftUI

/// A video thumbnail that automatically handles DeArrow integration.
///
/// This view wraps `VideoThumbnailView` and automatically:
/// - Fetches DeArrow branding when the view appears
/// - Displays the DeArrow thumbnail if available and enabled
/// - Falls back to the original thumbnail otherwise
/// - Shows live download progress from the download manager
///
/// Note: Download progress uses per-video dictionary observation. SwiftUI's @Observable
/// tracks dictionary access per-key, so this view only re-renders when THIS video's
/// progress changes - not when any other download progresses.
struct DeArrowVideoThumbnail: View {
    let video: Video

    var cornerRadius: CGFloat = 8
    var watchProgress: Double? = nil
    var duration: String? = nil
    var durationAlignment: Alignment = .bottomLeading

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var isWatched = false

    private var deArrowProvider: DeArrowBrandingProvider? {
        appEnvironment?.deArrowBrandingProvider
    }

    private var displayThumbnailURL: URL? {
        deArrowProvider?.thumbnailURL(for: video) ?? video.bestThumbnail?.url
    }

    #if !os(tvOS)
    private var downloadManager: DownloadManager? {
        appEnvironment?.downloadManager
    }

    /// Per-video download progress. Only triggers re-render when THIS video's progress changes.
    /// SwiftUI's @Observable tracks dictionary subscript access per-key.
    private var downloadProgressInfo: DownloadProgressInfo? {
        downloadManager?.downloadProgressByVideo[video.id]
    }

    /// Whether this video is fully downloaded (uses cached Set for O(1) lookup).
    private var isDownloaded: Bool {
        downloadManager?.isDownloaded(video.id) ?? false
    }

    private var downloadProgress: Double? {
        downloadProgressInfo?.progress
    }

    private var downloadProgressIndeterminate: Bool {
        downloadProgressInfo?.isIndeterminate ?? false
    }
    #else
    private var isDownloaded: Bool { false }
    private var downloadProgress: Double? { nil }
    private var downloadProgressIndeterminate: Bool { false }
    #endif

    /// Title to show on placeholder for media source videos without thumbnails.
    private var placeholderTitle: String? {
        guard displayThumbnailURL == nil, video.isFromMediaSource else { return nil }
        return video.title
    }

    /// Whether to show watched checkmark from settings.
    private var showWatchedCheckmark: Bool {
        appEnvironment?.settingsManager.showWatchedCheckmark ?? true
    }

    /// Whether this video has been fully watched.
    private var isFinishedWatching: Bool {
        guard showWatchedCheckmark else { return false }
        return isWatched
    }

    /// Updates the watched state from the data manager.
    private func updateWatchedState() {
        isWatched = appEnvironment?.dataManager.watchEntry(for: video.id.videoID)?.isFinished ?? false
    }

    var body: some View {
        VideoThumbnailView(
            url: displayThumbnailURL,
            cornerRadius: cornerRadius,
            watchProgress: watchProgress,
            duration: duration,
            durationAlignment: durationAlignment,
            isDownloaded: isDownloaded,
            downloadProgress: downloadProgress,
            downloadProgressIndeterminate: downloadProgressIndeterminate,
            isLive: video.isLive,
            placeholderTitle: placeholderTitle,
            isWatched: isFinishedWatching
        )
        .task(id: video.id) {
            deArrowProvider?.fetchIfNeeded(for: video)
        }
        .onAppear { updateWatchedState() }
        .onChange(of: video.id) { updateWatchedState() }
        .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
            updateWatchedState()
        }
    }
}

// MARK: - Preview

#Preview {
    DeArrowVideoThumbnail(
        video: .preview,
        watchProgress: 0.5,
        duration: "12:34"
    )
    .frame(width: 280)
    .padding()
}
