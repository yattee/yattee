//
//  ChapterRow.swift
//  Yattee
//
//  Row view for displaying a video chapter.
//

import SwiftUI

struct ChapterRow: View {
    let chapter: VideoChapter
    let isActive: Bool
    let storyboard: Storyboard?
    let onTap: () -> Void

    @State private var thumbnail: PlatformImage?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Thumbnail from storyboard
                Group {
                    if let thumbnail {
                        #if os(macOS)
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                        #else
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                        #endif
                    } else {
                        Rectangle()
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: "film")
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 80, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(chapter.title)
                        .font(.subheadline)
                        .fontWeight(isActive ? .semibold : .regular)
                        .lineLimit(2)

                    Text(chapter.formattedStartTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                // Active indicator
                if isActive {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(isActive ? Color.accentColor.opacity(0.1) : nil)
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard let storyboard else { return }

        let service = StoryboardService.shared

        // Try cached first
        if let cached = await service.thumbnail(for: chapter.startTime, from: storyboard) {
            thumbnail = cached
            return
        }

        // Load the sheet
        await service.preloadNearbySheets(around: chapter.startTime, from: storyboard)

        // Try again after loading
        if let loaded = await service.thumbnail(for: chapter.startTime, from: storyboard) {
            thumbnail = loaded
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        ChapterRow(
            chapter: VideoChapter(title: "Introduction", startTime: 0),
            isActive: true,
            storyboard: nil,
            onTap: {}
        )
        ChapterRow(
            chapter: VideoChapter(title: "Main Content", startTime: 60),
            isActive: false,
            storyboard: nil,
            onTap: {}
        )
    }
    .listStyle(.plain)
}
