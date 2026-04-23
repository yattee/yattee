//
//  BookmarkCardView.swift
//  Yattee
//
//  Grid card view for displaying bookmarked videos with tags and notes.
//

import SwiftUI

/// A bookmark card for grid/horizontal scroll layouts.
/// Displays video content via VideoCardView with additional tags/notes.
struct BookmarkCardView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let bookmark: Bookmark
    var watchProgress: Double? = nil
    /// Use compact styling for dense grids (3+ columns).
    var isCompact: Bool = false

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

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 8) {
            // Video card content
            VideoCardView(
                video: video,
                watchProgress: watchProgress,
                isCompact: isCompact
            )
            
            // Tags and notes - one line
            if hasMetadata {
                bookmarkMetadataLine
            }
        }
        .contentShape(Rectangle())
    }
    
    /// Single line with tags and note separated by dot (or icons in compact mode)
    @ViewBuilder
    private var bookmarkMetadataLine: some View {
        if isCompact {
            // Compact mode: show only icons
            HStack(spacing: 4) {
                if hasTags {
                    Image(systemName: "tag.fill")
                        .font(.caption2)
                        .foregroundStyle(accentColor)
                }
                if hasNote {
                    Image(systemName: "text.page")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            // Regular mode: tags and note in one line
            HStack(spacing: 4) {
                if hasTags {
                    BookmarkTagsView(
                        tags: bookmark.tags,
                        maxVisible: 2
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
}

// MARK: - Preview

#Preview("Card") {
    BookmarkCardView(
        bookmark: .preview,
        watchProgress: 0.4
    )
    .frame(width: 280)
    .padding()
    .appEnvironment(.preview)
}

#Preview("Card Compact") {
    BookmarkCardView(
        bookmark: .preview,
        watchProgress: 0.4,
        isCompact: true
    )
    .frame(width: 110)
    .padding()
    .appEnvironment(.preview)
}
