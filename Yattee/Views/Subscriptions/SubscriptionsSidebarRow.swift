//
//  SubscriptionsSidebarRow.swift
//  Yattee
//
//  Compact row used in the Subscriptions sidebar (macOS and iPad) for the
//  "All Channels" entry and each subscribed channel.
//

import SwiftUI
import NukeUI

struct SubscriptionsSidebarRow: View {
    let name: String
    let avatarURL: URL?
    let serverURL: URL?
    let authHeader: String?
    let channelID: String?
    let isAllChannels: Bool
    var isSelected: Bool = false

    private let avatarSize: CGFloat = 28

    private var effectiveAvatarURL: URL? {
        guard let channelID else { return nil }
        return AvatarURLBuilder.avatarURL(
            channelID: channelID,
            directURL: avatarURL,
            serverURL: serverURL,
            size: Int(avatarSize * 2)
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            avatar
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())

            Text(name)
                .fontWeight(isSelected ? .semibold : .regular)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var avatar: some View {
        if isAllChannels {
            ZStack {
                Circle().fill(.quaternary)
                Image(systemName: "rectangle.stack.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
                    .padding(avatarSize * 0.25)
            }
        } else {
            LazyImage(request: AvatarURLBuilder.imageRequest(url: effectiveAvatarURL, authHeader: authHeader)) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Circle()
                        .fill(.quaternary)
                        .overlay {
                            Text(String(name.prefix(1)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                }
            }
        }
    }
}
