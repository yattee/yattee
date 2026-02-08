//
//  ChannelCardGridView.swift
//  Yattee
//
//  A channel card component for grid layouts.
//

import SwiftUI
import NukeUI

/// A channel card for grid layouts.
///
/// Displays channel avatar, name, subscriber count, and verified badge
/// with a subtle background card style.
struct ChannelCardGridView: View {
    let channel: Channel
    var isCompact: Bool = false
    var authHeader: String?

    private var avatarSize: CGFloat { isCompact ? 80 : 100 }
    private var titleFont: Font { isCompact ? .caption : .subheadline }
    private var subscriberFont: Font { isCompact ? .caption2 : .caption }

    /// Minimum height for channel name to reserve space for 2 lines
    private var titleMinHeight: CGFloat { isCompact ? 32 : 40 }

    var body: some View {
        VStack(alignment: .center, spacing: isCompact ? 8 : 12) {
            // Avatar
            LazyImage(request: AvatarURLBuilder.imageRequest(url: channel.thumbnailURL, authHeader: authHeader)) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    avatarPlaceholder
                }
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
            
            // Channel info
            VStack(alignment: .center, spacing: 4) {
                Text(channel.name)
                    .font(titleFont)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: titleMinHeight, alignment: .top)
                
                // Subscriber count row - reserve space even when nil
                HStack(spacing: 4) {
                    if let subscribers = channel.formattedSubscriberCount {
                        Text(subscribers)
                            .font(subscriberFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        
                        if channel.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        // Reserve space with invisible text
                        Text(verbatim: " ")
                            .font(subscriberFont)
                    }
                }
                .frame(minHeight: isCompact ? 14 : 16)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }
    
    private var avatarPlaceholder: some View {
        Circle()
            .fill(.quaternary)
            .overlay {
                Text(String(channel.name.prefix(1)))
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
    }
}

// MARK: - Preview

#Preview("Regular") {
    ChannelCardGridView(
        channel: Channel(
            id: ChannelID(source: .global(provider: ContentSource.youtubeProvider), channelID: "UC1"),
            name: "Apple Developer",
            description: nil,
            subscriberCount: 1500000,
            videoCount: nil,
            thumbnailURL: nil,
            bannerURL: nil,
            isVerified: true
        )
    )
    .frame(width: 200)
    .padding()
}

#Preview("Compact") {
    ChannelCardGridView(
        channel: Channel(
            id: ChannelID(source: .global(provider: ContentSource.youtubeProvider), channelID: "UC1"),
            name: "Apple Developer",
            description: nil,
            subscriberCount: 1500000,
            videoCount: nil,
            thumbnailURL: nil,
            bannerURL: nil,
            isVerified: true
        ),
        isCompact: true
    )
    .frame(width: 150)
    .padding()
}
