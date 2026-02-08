//
//  PlaylistCardView.swift
//  Yattee
//
//  A playlist card component for grid layouts.
//

import SwiftUI
import NukeUI

/// A playlist card for grid layouts.
///
/// Displays thumbnail with video count badge, title, and author name.
struct PlaylistCardView: View {
    let playlist: Playlist
    var isCompact: Bool = false
    
    private var titleFont: Font { isCompact ? .caption : .subheadline }
    private var authorFont: Font { isCompact ? .caption2 : .caption }
    
    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 8) {
            // Thumbnail with video count badge - fixed 16:9 aspect ratio container
            Color.clear
                .aspectRatio(16/9, contentMode: .fit)
                .overlay {
                    LazyImage(url: playlist.thumbnailURL) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            thumbnailPlaceholder
                        }
                    }
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: isCompact ? 6 : 8))
                .overlay(alignment: .bottomTrailing) {
                    if playlist.videoCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "play.square.stack")
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
            
            // Metadata - fixed height to ensure consistent card sizes in grid
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.title)
                    .font(titleFont)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Text(playlist.authorName)
                    .font(authorFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Spacer(minLength: 0)
            }
            .frame(height: isCompact ? 50 : 58)
        }
        .contentShape(Rectangle())
    }
    
    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: isCompact ? 6 : 8)
            .fill(.quaternary)
            .aspectRatio(16/9, contentMode: .fill)
            .overlay {
                Image(systemName: "play.square.stack")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }
}

// MARK: - Preview

#Preview("Regular") {
    PlaylistCardView(
        playlist: Playlist(
            id: PlaylistID(source: .global(provider: ContentSource.youtubeProvider), playlistID: "PL1"),
            title: "SwiftUI Tutorials for Beginners",
            author: Author(id: "UC1", name: "Apple Developer"),
            videoCount: 25,
            thumbnailURL: nil
        )
    )
    .frame(width: 200)
    .padding()
}

#Preview("Compact") {
    PlaylistCardView(
        playlist: Playlist(
            id: PlaylistID(source: .global(provider: ContentSource.youtubeProvider), playlistID: "PL1"),
            title: "SwiftUI Tutorials for Beginners",
            author: Author(id: "UC1", name: "Apple Developer"),
            videoCount: 25,
            thumbnailURL: nil
        ),
        isCompact: true
    )
    .frame(width: 150)
    .padding()
}
