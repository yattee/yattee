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

    /// Optional transforms applied to the icon and text regions so callers
    /// (e.g. MediaFileTapModifier) can attach per-region gestures.
    var iconAreaModifier: (AnyView) -> AnyView = { $0 }
    var textAreaModifier: (AnyView) -> AnyView = { $0 }

    init(
        file: MediaFile,
        sortOrder: MediaBrowserSortOrder = .name,
        iconAreaModifier: @escaping (AnyView) -> AnyView = { $0 },
        textAreaModifier: @escaping (AnyView) -> AnyView = { $0 }
    ) {
        self.file = file
        self.sortOrder = sortOrder
        self.iconAreaModifier = iconAreaModifier
        self.textAreaModifier = textAreaModifier
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
        HStack(spacing: 12) {
            iconAreaModifier(AnyView(iconView))
            textAreaModifier(AnyView(textView))
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var iconView: some View {
        Image(systemName: file.systemImage)
            .font(.title2)
            .foregroundStyle(iconColor)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private var textView: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        MediaFileRow(file: .folderPreview)
        MediaFileRow(file: .preview)
        MediaFileRow(
            file: MediaFile(
                source: .webdav(name: "NAS", url: URL(string: "https://nas.local")!),
                path: "/Music/song.mp3",
                name: "song.mp3",
                isDirectory: false,
                size: 5_000_000,
                modifiedDate: Date()
            )
        )
    }
}
