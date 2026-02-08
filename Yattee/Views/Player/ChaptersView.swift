//
//  ChaptersView.swift
//  Yattee
//
//  View for displaying and navigating video chapters.
//

import SwiftUI

struct ChaptersView: View {
    let chapters: [VideoChapter]
    let currentTime: TimeInterval
    let storyboard: Storyboard?
    let onChapterTap: (VideoChapter) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sheetsLoaded = false

    var body: some View {
        NavigationStack {
            Group {
                if sheetsLoaded {
                    chaptersList
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(String(localized: "player.chapters"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Label(String(localized: "common.close"), systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .task {
                await preloadChapterSheets()
                sheetsLoaded = true
            }
        }
    }

    private var chaptersList: some View {
        List {
            ForEach(chapters) { chapter in
                ChapterRow(
                    chapter: chapter,
                    isActive: isChapterActive(chapter),
                    storyboard: storyboard,
                    onTap: {
                        Task {
                            await onChapterTap(chapter)
                            dismiss()
                        }
                    }
                )
            }
        }
        .listStyle(.plain)
    }

    private func preloadChapterSheets() async {
        guard let storyboard else { return }
        let service = StoryboardService.shared

        // Preload sheets for all chapter start times
        for chapter in chapters {
            await service.loadSheet(for: chapter.startTime, from: storyboard)
        }
    }

    private func isChapterActive(_ chapter: VideoChapter) -> Bool {
        let nextChapter = chapters.first { $0.startTime > chapter.startTime }
        let endTime = nextChapter?.startTime ?? .infinity
        return currentTime >= chapter.startTime && currentTime < endTime
    }
}

// MARK: - Preview

#Preview {
    ChaptersView(
        chapters: [
            VideoChapter(title: "Introduction", startTime: 0),
            VideoChapter(title: "Main Content", startTime: 60),
            VideoChapter(title: "Deep Dive", startTime: 180),
            VideoChapter(title: "Conclusion", startTime: 300),
        ],
        currentTime: 90,
        storyboard: nil,
        onChapterTap: { _ in }
    )
}
