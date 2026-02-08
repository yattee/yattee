//
//  ChannelPlaylistRow.swift
//  Yattee
//
//  Row view for displaying a playlist in channel playlists tab.
//

import SwiftUI
import NukeUI

struct ChannelPlaylistRow: View {
    let playlist: Playlist
    var style: VideoRowStyle = .regular

    // Size configuration based on style (unified with VideoRowStyle)
    private var thumbnailWidth: CGFloat {
        style.thumbnailWidth
    }

    private var thumbnailHeight: CGFloat {
        style.thumbnailHeight
    }

    private var titleFont: Font {
        switch style {
        case .large: return .body
        case .regular: return .subheadline
        case .compact: return .caption
        }
    }

    private var titleLineLimit: Int {
        switch style {
        case .large: return 3
        case .regular: return 2
        case .compact: return 1
        }
    }

    private var cornerRadius: CGFloat {
        style == .compact ? 4 : 8
    }

    var body: some View {
        NavigationLink(value: NavigationDestination.playlist(.remote(playlist.id, instance: nil, title: playlist.title))) {
            HStack(spacing: 12) {
                // Thumbnail
                LazyImage(url: playlist.thumbnailURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        thumbnailPlaceholder
                    }
                }
                .frame(width: thumbnailWidth, height: thumbnailHeight)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(alignment: .bottomTrailing) {
                    if style != .compact {
                        videoCountBadge
                    }
                }

                // Info
                VStack(alignment: .leading, spacing: style == .compact ? 2 : 4) {
                    Text(playlist.title)
                        .font(titleFont)
                        .fontWeight(.medium)
                        .lineLimit(titleLineLimit)

                    if style != .compact && !playlist.authorName.isEmpty {
                        Text(playlist.authorName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if style == .compact {
                        Text("\(playlist.videoCount) videos")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("playlist.videoCount \(playlist.videoCount)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
        }
        .zoomTransitionSource(id: playlist.id)
        .buttonStyle(.plain)
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(style == .compact ? .caption : .title2)
                    .foregroundStyle(.secondary)
            }
    }

    private var videoCountBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "play.rectangle.fill")
                .font(.caption2)
            Text("\(playlist.videoCount)")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.black.opacity(0.75))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(6)
    }
}
