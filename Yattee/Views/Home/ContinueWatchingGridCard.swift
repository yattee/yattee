//
//  ContinueWatchingGridCard.swift
//  Yattee
//
//  Grid card view for continue watching items.
//

import SwiftUI

struct TappableContinueWatchingGridCard: View {
    let entry: WatchEntry
    let onRemove: () -> Void

    private var video: Video {
        entry.toVideo()
    }

    var body: some View {
        ContinueWatchingGridCard(entry: entry)
            .tappableVideo(
                video,
                startTime: entry.watchedSeconds,
                queueSource: .manual,
                sourceLabel: String(localized: "queue.source.continueWatching")
            )
            .videoContextMenu(
                video: video,
                customActions: [
                    VideoContextAction(
                        String(localized: "continueWatching.remove"),
                        systemImage: "xmark.circle",
                        role: .destructive,
                        action: onRemove
                    )
                ],
                context: .continueWatching,
                startTime: entry.watchedSeconds
            )
    }
}

/// Grid card for continue watching items with automatic DeArrow support.
struct ContinueWatchingGridCard: View {
    let entry: WatchEntry

    private var video: Video {
        entry.toVideo()
    }

    var body: some View {
        VideoCardView(
            video: video,
            watchProgress: entry.progress,
            customMetadata: entry.isFinished ? nil : String(localized: "home.history.remaining \(entry.remainingTime)"),
            customDuration: entry.remainingTime
        )
    }
}

// MARK: - Preview
// Note: Preview requires a WatchEntry object from SwiftData context.
// See ContinueWatchingView.swift for usage examples.
