//
//  SidebarChannelRow.swift
//  Yattee
//
//  Compact channel row for sidebar display.
//

import SwiftUI
import NukeUI

struct SidebarChannelRow: View {
    let name: String
    let avatarURL: URL?
    var authHeader: String?

    var body: some View {
        HStack(spacing: 8) {
            // Avatar
            LazyImage(request: AvatarURLBuilder.imageRequest(url: avatarURL, authHeader: authHeader)) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    avatarPlaceholder
                }
            }
            .frame(width: 24, height: 24)
            .clipShape(Circle())

            // Name
            Text(name)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(.quaternary)
            .overlay {
                Text(String(name.prefix(1)).uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
    }
}

// MARK: - Preview

#if !os(tvOS)
#Preview {
    List {
        SidebarChannelRow(
            name: "Technology Reviews",
            avatarURL: nil
        )
        SidebarChannelRow(
            name: "Music & Sound Design",
            avatarURL: nil
        )
        SidebarChannelRow(
            name: "A Very Long Channel Name That Should Be Truncated",
            avatarURL: nil
        )
    }
    .listStyle(.sidebar)
}
#endif
