//
//  PlaylistVideoRowView.swift
//  Yattee
//
//  Unified row view for playlist videos (both remote and local playlists).
//

import SwiftUI

/// Unified row view for displaying videos in playlists.
/// Used by UnifiedPlaylistDetailView for both remote and local playlists.
/// Uses VideoRowView for consistent presentation with automatic DeArrow integration.
struct PlaylistVideoRowView: View {
    let index: Int
    let video: Video
    var watchProgress: Double? = nil
    var onRemove: (() -> Void)? = nil

    var body: some View {
        VideoRowView(
            video: video,
            style: .regular,
            watchProgress: watchProgress,
            index: index
        )
        .videoContextMenu(
            video: video,
            customActions: onRemove.map { removeAction in
                [VideoContextAction(
                    String(localized: "playlist.removeVideo"),
                    systemImage: "trash",
                    role: .destructive,
                    action: removeAction
                )]
            } ?? [],
            context: .playlist
        )
    }
}

// MARK: - Convenience Initializers

extension PlaylistVideoRowView {
    /// Initialize from a LocalPlaylistItem model.
    init(item: LocalPlaylistItem, index: Int, watchProgress: Double? = nil, onRemove: @escaping () -> Void) {
        self.index = index
        self.video = item.toVideo()
        self.watchProgress = watchProgress
        self.onRemove = onRemove
    }
}

// MARK: - Preview

#Preview {
    List {
        PlaylistVideoRowView(
            index: 1,
            video: .preview
        )
        PlaylistVideoRowView(
            index: 2,
            video: .preview,
            onRemove: {}
        )
    }
}
