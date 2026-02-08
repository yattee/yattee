//
//  ChannelAvatarView.swift
//  Yattee
//
//  Channel avatar that supports loading from Yattee Server.
//  When the author doesn't have a thumbnail URL (common with yt-dlp),
//  this view will attempt to load the avatar from the server's avatar endpoint.
//

import SwiftUI
import NukeUI

// MARK: - Channel Avatar View

/// A channel avatar view that supports loading from Yattee Server.
struct ChannelAvatarView: View {
    let author: Author
    let size: CGFloat
    let yatteeServerURL: URL?
    let source: ContentSource?

    init(author: Author, size: CGFloat = 40, yatteeServerURL: URL? = nil, source: ContentSource? = nil) {
        self.author = author
        self.size = size
        self.yatteeServerURL = yatteeServerURL
        self.source = source
    }

    var body: some View {
        LazyImage(url: avatarURL) { state in
            ZStack {
                // Background circle with letter placeholder
                Circle()
                    .fill(.quaternary)
                    .overlay {
                        if state.image == nil {
                            Text(String(author.name.prefix(1)))
                                .font(size > 50 ? .title : .subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }

                // Avatar image
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        // Isolate geometry to prevent position jumping during parent animations
        .geometryGroup()
    }

    /// Constructs the avatar URL from author's thumbnail or Yattee Server.
    private var avatarURL: URL? {
        // Primary: Use author's thumbnail URL if available
        if let authorURL = author.thumbnailURL {
            return authorURL
        }

        guard let serverURL = yatteeServerURL, !author.id.isEmpty else {
            return nil
        }

        // Only use Yattee Server fallback for YouTube sources
        // Non-YouTube sources (extracted, federated) cannot use the avatar endpoint
        if let source = source {
            switch source {
            case .global(let provider):
                guard provider == ContentSource.youtubeProvider else {
                    return nil
                }
            case .federated, .extracted:
                return nil
            }
        }

        // Construct URL from Yattee Server - server handles fetching/caching
        let avatarSize = Int(size * 2) // 2x for retina
        let roundedSize = [32, 48, 76, 100, 176, 512].min { abs($0 - avatarSize) < abs($1 - avatarSize) } ?? 176

        return serverURL
            .appendingPathComponent("api/v1/channels")
            .appendingPathComponent(author.id)
            .appendingPathComponent("avatar")
            .appendingPathComponent("\(roundedSize).jpg")
    }
}
