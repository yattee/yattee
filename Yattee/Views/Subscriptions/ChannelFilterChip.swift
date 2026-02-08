//
//  ChannelFilterChip.swift
//  Yattee
//
//  Channel avatar chip for filtering subscriptions.
//

import SwiftUI
import NukeUI

struct ChannelFilterChip: View {
    let channelID: String
    let name: String
    let avatarURL: URL?
    let serverURL: URL?
    let isSelected: Bool
    let avatarSize: CGFloat
    let onTap: () -> Void
    let onGoToChannel: (() -> Void)?
    let onUnsubscribe: (() -> Void)?
    var authHeader: String?

    private var effectiveAvatarURL: URL? {
        AvatarURLBuilder.avatarURL(
            channelID: channelID,
            directURL: avatarURL,
            serverURL: serverURL,
            size: Int(avatarSize)
        )
    }

    var body: some View {
        Button(action: onTap) {
            LazyImage(request: AvatarURLBuilder.imageRequest(url: effectiveAvatarURL, authHeader: authHeader)) { state in
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
            .overlay {
                Circle()
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            }
            .scaleEffect(isSelected ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onGoToChannel {
                Button(action: onGoToChannel) {
                    Label(String(localized: "subscriptions.goToChannel"), systemImage: "person.circle")
                }
            }
            if let onUnsubscribe {
                Button(role: .destructive, action: onUnsubscribe) {
                    Label(String(localized: "channel.unsubscribe"), systemImage: "person.badge.minus")
                }
            }
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(.quaternary)
            .overlay {
                Text(String(name.prefix(1)))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        Text("Without context menu")
            .font(.caption)
            .foregroundStyle(.secondary)
        
        HStack(spacing: 12) {
            ChannelFilterChip(
                channelID: "UCtest123",
                name: "Tech Channel",
                avatarURL: nil,
                serverURL: nil,
                isSelected: false,
                avatarSize: 44,
                onTap: {},
                onGoToChannel: nil,
                onUnsubscribe: nil
            )
            ChannelFilterChip(
                channelID: "UCtest456",
                name: "Music",
                avatarURL: nil,
                serverURL: nil,
                isSelected: true,
                avatarSize: 44,
                onTap: {},
                onGoToChannel: nil,
                onUnsubscribe: nil
            )
        }
        
        Text("With full context menu")
            .font(.caption)
            .foregroundStyle(.secondary)
        
        HStack(spacing: 12) {
            ChannelFilterChip(
                channelID: "UCtest789",
                name: "Gaming",
                avatarURL: nil,
                serverURL: nil,
                isSelected: false,
                avatarSize: 44,
                onTap: {},
                onGoToChannel: {},
                onUnsubscribe: {}
            )
        }
    }
    .padding()
}
