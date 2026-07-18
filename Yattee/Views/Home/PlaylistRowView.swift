//
//  PlaylistRowView.swift
//  Yattee
//
//  Row view for displaying a playlist in lists.
//

import SwiftUI
import NukeUI

struct PlaylistRowView: View {
    let playlist: LocalPlaylist

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            LazyImage(url: playlist.thumbnailURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "music.note.list")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 80, height: 45)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.title)
                    .font(.headline)
                    .lineLimit(1)

                Text("playlist.videoCountDuration \(playlist.videoCount) \(playlist.formattedTotalDuration)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
