//
//  WatchEntryRowView.swift
//  Yattee
//
//  Unified row view for displaying watch history or continue watching entries.
//

import SwiftUI

/// Unified row view for displaying watch history or continue watching entries.
/// Uses VideoRowView for consistent presentation.
/// Automatically handles DeArrow integration and includes tap-to-play functionality.
/// Supports optional queue context for auto-play functionality.
/// Password checking for WebDAV sources is handled by TappableVideoModifier.
struct WatchEntryRowView: View {
    let entry: WatchEntry
    let onRemove: () -> Void
    var startTime: Double? = nil
    
    // Queue context (optional, enables auto-play when provided)
    var queueSource: QueueSource? = nil
    var sourceLabel: String? = nil
    var videoList: [Video]? = nil
    var videoIndex: Int? = nil
    var loadMoreVideos: LoadMoreVideosCallback? = nil

    private var video: Video {
        entry.toVideo()
    }

    var body: some View {
        VideoRowView(
            video: video,
            style: .regular,
            watchProgress: entry.progress,
            customMetadata: entry.isFinished ? nil : String(localized: "home.history.remaining \(entry.remainingTime)")
        )
        .tappableVideo(
            video,
            startTime: startTime ?? entry.watchedSeconds,
            queueSource: queueSource,
            sourceLabel: sourceLabel,
            videoList: videoList,
            videoIndex: videoIndex,
            loadMoreVideos: loadMoreVideos
        )
        .videoContextMenu(
            video: video,
            customActions: [
                VideoContextAction(
                    String(localized: "home.history.remove"),
                    systemImage: "trash",
                    role: .destructive,
                    action: onRemove
                )
            ],
            context: .history,
            startTime: startTime ?? entry.watchedSeconds
        )
    }
}
