//
//  TappablePlaylistVideoRow.swift
//  Yattee
//
//  Tappable row view for playlist videos.
//

import SwiftUI

/// A playlist video row that plays the video when tapped.
///
/// Note: For new code, consider using `PlaylistVideoRowView(...).tappableVideo(video, includeContextMenu: false)` directly.
struct TappablePlaylistVideoRow: View {
    let video: Video
    let index: Int

    var body: some View {
        PlaylistVideoRowView(
            index: index,
            video: video
        )
        .padding(.horizontal)
        .padding(.vertical, 8)
        .tappableVideo(video, includeContextMenu: false)
    }
}

// MARK: - Preview

#Preview {
    List {
        TappablePlaylistVideoRow(
            video: Video(
                id: .global("test"),
                title: "Test Video",
                description: nil,
                author: Author(id: "author", name: "Test Channel"),
                duration: 360,
                publishedAt: nil,
                publishedText: "2 days ago",
                viewCount: 10000,
                likeCount: nil,
                thumbnails: [],
                isLive: false,
                isUpcoming: false,
                scheduledStartTime: nil
            ),
            index: 1
        )
    }
    .appEnvironment(.preview)
}
