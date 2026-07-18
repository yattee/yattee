//
//  SidebarPlaylistRow.swift
//  Yattee
//
//  Compact playlist row for sidebar display.
//

import SwiftUI

struct SidebarPlaylistRow: View {
    let title: String
    let videoCount: Int

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            // Title and count
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            // Video count badge
            if videoCount > 0 {
                Text("\(videoCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#if !os(tvOS)
#Preview {
    List {
        SidebarPlaylistRow(
            title: "Watch Later",
            videoCount: 12
        )
        SidebarPlaylistRow(
            title: "Favorites",
            videoCount: 45
        )
        SidebarPlaylistRow(
            title: "A Very Long Playlist Name That Should Be Truncated",
            videoCount: 100
        )
        SidebarPlaylistRow(
            title: "Empty Playlist",
            videoCount: 0
        )
    }
    .listStyle(.sidebar)
}
#endif
