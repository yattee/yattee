//
//  BookmarkRowView.swift
//  Yattee
//
//  Row view for displaying bookmarked videos with tags and notes.
//

import SwiftUI

/// Row view for displaying bookmarked videos.
/// Uses VideoRowView for consistent presentation with additional tags/notes display.
/// Automatically handles DeArrow integration.
/// Supports optional queue context for auto-play functionality.
struct BookmarkRowView: View {
    let bookmark: Bookmark
    var style: VideoRowStyle = .regular
    var watchProgress: Double? = nil
    let onRemove: () -> Void

    // Queue context (optional, enables auto-play when provided)
    var queueSource: QueueSource? = nil
    var sourceLabel: String? = nil
    var videoList: [Video]? = nil
    var videoIndex: Int? = nil
    var loadMoreVideos: LoadMoreVideosCallback? = nil

    @Environment(\.appEnvironment) private var appEnvironment

    private var accentColor: Color {
        appEnvironment?.settingsManager.accentColor.color ?? .accentColor
    }

    private var video: Video {
        bookmark.toVideo()
    }

    private var hasTags: Bool {
        !bookmark.tags.isEmpty
    }

    private var hasNote: Bool {
        if let note = bookmark.note, !note.isEmpty {
            return true
        }
        return false
    }

    private var hasMetadata: Bool {
        hasTags || hasNote
    }

    /// Leading padding to align tags/notes with the text content (past thumbnail)
    private var metadataLeadingPadding: CGFloat {
        let hstackSpacing: CGFloat = 12
        return style.thumbnailWidth + hstackSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Video row content
            videoRowContent

            // Tags and notes (text-aligned, past thumbnail) - one line
            if hasMetadata && style != .compact {
                bookmarkMetadataLine
                    .padding(.leading, metadataLeadingPadding)
                    .padding(.top, 4)
            }
        }
        .tappableVideo(
            video,
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
                    String(localized: "home.bookmarks.remove"),
                    systemImage: "trash",
                    role: .destructive,
                    action: onRemove
                )
            ],
            context: .bookmarks
        )
    }

    @ViewBuilder
    private var videoRowContent: some View {
        VideoRowView(
            video: video,
            style: style,
            watchProgress: watchProgress
        )
    }

    /// Single line with tags and note separated by dot
    @ViewBuilder
    private var bookmarkMetadataLine: some View {
        HStack(spacing: 4) {
            if hasTags {
                BookmarkTagsView(
                    tags: bookmark.tags,
                    maxVisible: style == .large ? 4 : 3
                )
            }

            if hasTags && hasNote {
                Text(verbatim: "·")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if hasNote {
                Text(bookmark.note!)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
