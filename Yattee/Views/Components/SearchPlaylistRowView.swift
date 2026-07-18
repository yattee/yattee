//
//  SearchPlaylistRowView.swift
//  Yattee
//
//  A row view for displaying playlist information in search results.
//

import SwiftUI
import NukeUI

struct SearchPlaylistRowView: View {
    let playlist: Playlist
    var style: VideoRowStyle = .regular
    
    // Style-based dimensions
    private var thumbnailWidth: CGFloat {
        style.thumbnailWidth
    }
    
    private var thumbnailHeight: CGFloat {
        style.thumbnailHeight
    }
    
    private var cornerRadius: CGFloat {
        switch style {
        case .large: return 8
        case .regular: return 6
        case .compact: return 4
        }
    }
    
    private var titleLines: Int {
        switch style {
        case .large: return 3
        case .regular: return 2
        case .compact: return 1
        }
    }
    
    private var titleFont: Font {
        #if os(tvOS)
        style == .compact ? .caption : .subheadline
        #else
        .subheadline
        #endif
    }
    
    private var authorFont: Font {
        #if os(tvOS)
        style == .compact ? .caption2 : .caption
        #else
        style == .compact ? .caption2 : .caption
        #endif
    }

    var body: some View {
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
                if playlist.videoCount > 0 {
                    Text("\(playlist.videoCount)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.75))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.title)
                    .font(titleFont)
                    .fontWeight(.medium)
                    .lineLimit(titleLines)

                Text(playlist.authorName)
                    .font(authorFont)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(.secondary)
            }
    }
}
