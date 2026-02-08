//
//  CommentsPillView.swift
//  Yattee
//
//  A rounded pill showing a comment preview that slides in from the bottom.
//  Tapping expands to full comments view.
//  Collapses to just avatar when isCollapsed is true.
//

import SwiftUI
import NukeUI

struct CommentsPillView: View {
    let comment: Comment
    let isCollapsed: Bool
    var fillWidth: Bool = false
    /// When true, uses smaller sizing for the collapsed state (e.g. on narrow devices).
    var compact: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: isCollapsed ? 0 : 12) {
                // Show icon when collapsed, avatar when expanded
                if isCollapsed {
                    collapsedIconView
                } else {
                    avatarView
                }

                // Text content - only in layout when expanded
                if !isCollapsed {
                    textContent
                }
            }
            .frame(maxWidth: (!isCollapsed && fillWidth) ? .infinity : nil, alignment: .leading)
            .padding(.horizontal, isCollapsed ? (compact ? 6 : 10) : 16)
            .padding(.vertical, isCollapsed ? (compact ? 6 : 10) : 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .glassBackground(.regular, in: .capsule, fallback: .thinMaterial)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
    }

    private var collapsedIconView: some View {
        let size: CGFloat = compact ? 28 : 32
        return Image(systemName: "bubble.left.and.bubble.right")
            .font(.system(size: compact ? 16 : 18, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
    }

    private var avatarView: some View {
        LazyImage(url: comment.author.thumbnailURL) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Circle()
                    .fill(.quaternary)
                    .overlay {
                        Text(String(comment.author.name.prefix(1)))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Author name
            Text(comment.author.name)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)

            // 2-line excerpt of comment
            Text(comment.content)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
