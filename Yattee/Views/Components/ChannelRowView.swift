//
//  ChannelRowView.swift
//  Yattee
//
//  A row view for displaying channel information in search results.
//

import SwiftUI
import NukeUI

struct ChannelRowView: View {
    let channel: Channel
    var style: VideoRowStyle = .regular
    var authHeader: String?

    // Style-based dimensions - use thumbnail height to keep avatar square and match row height
    private var avatarSize: CGFloat {
        style.thumbnailHeight
    }

    private var nameLines: Int {
        switch style {
        case .large: return 2
        case .regular: return 1
        case .compact: return 1
        }
    }

    private var nameFont: Font {
        #if os(tvOS)
        style == .compact ? .caption : .subheadline
        #else
        .subheadline
        #endif
    }

    private var subscriberFont: Font {
        #if os(tvOS)
        style == .compact ? .caption2 : .caption
        #else
        style == .compact ? .caption2 : .caption
        #endif
    }

    private var showChevron: Bool {
        style != .compact
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar - centered in container with same width as video thumbnail
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
            .frame(width: style.thumbnailWidth)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name)
                    .font(nameFont)
                    .fontWeight(.medium)
                    .lineLimit(nameLines)

                if let subscribers = channel.formattedSubscriberCount {
                    HStack(spacing: 4) {
                        Text(String(localized: "channel.subscriberCount \(subscribers)"))
                            .font(subscriberFont)
                            .foregroundStyle(.secondary)
                        
                        if channel.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            if showChevron {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(.quaternary)
            .overlay {
                Text(String(channel.name.prefix(1)))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
    }
}
