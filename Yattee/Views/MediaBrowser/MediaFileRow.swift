//
//  MediaFileRow.swift
//  Yattee
//
//  Row view for displaying a file or folder in the media browser.
//

import SwiftUI

struct MediaFileRow: View {
    let file: MediaFile
    let sortOrder: MediaBrowserSortOrder
    let action: (() -> Void)?

    /// Initialize with an action (for playable files).
    init(file: MediaFile, sortOrder: MediaBrowserSortOrder = .name, action: @escaping () -> Void) {
        self.file = file
        self.sortOrder = sortOrder
        self.action = action
    }

    /// Initialize without action (for use inside NavigationLink).
    init(file: MediaFile, sortOrder: MediaBrowserSortOrder = .name) {
        self.file = file
        self.sortOrder = sortOrder
        self.action = nil
    }

    /// The date to display based on current sort order.
    private var displayDate: Date? {
        switch sortOrder {
        case .name, .dateModified:
            file.modifiedDate
        case .dateCreated:
            file.createdDate
        }
    }

    var body: some View {
        if let action {
            Button(action: action) {
                rowContent
            }
            .buttonStyle(.plain)
            .if(file.isPlayable) { view in
                view.videoContextMenu(
                    video: file.toVideo(),
                    context: .mediaBrowser
                )
            }
        } else {
            rowContent
                .if(file.isPlayable) { view in
                    view.videoContextMenu(
                        video: file.toVideo(),
                        context: .mediaBrowser
                    )
                }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: file.systemImage)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.body)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    if let size = file.formattedSize {
                        Text(size)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let date = displayDate {
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }

    private var iconColor: Color {
        if file.isDirectory {
            return .blue
        }
        if file.isVideo {
            return .purple
        }
        if file.isAudio {
            return .pink
        }
        return .secondary
    }
}

// MARK: - Preview

#Preview {
    List {
        MediaFileRow(file: .folderPreview) {}
        MediaFileRow(file: .preview) {}
        MediaFileRow(
            file: MediaFile(
                source: .webdav(name: "NAS", url: URL(string: "https://nas.local")!),
                path: "/Music/song.mp3",
                name: "song.mp3",
                isDirectory: false,
                size: 5_000_000,
                modifiedDate: Date()
            )
        ) {}
    }
}
