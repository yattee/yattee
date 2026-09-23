//
//  ChaptersPanelPage.swift
//  Yattee
//
//  Details panel page listing video chapters; tapping seeks.
//

import SwiftUI

#if os(iOS) || os(macOS)

struct ChaptersPanelPage: View {
    let context: PanelPageContext
    var settings: ChaptersPageSettings = ChaptersPageSettings()
    var scrollConfig: PanelScrollConfig = PanelScrollConfig()

    private var appEnvironment: AppEnvironment? { context.appEnvironment }
    private var playerService: PlayerService? { appEnvironment?.playerService }
    private var playerState: PlayerState? { playerService?.state }

    private var chapters: [VideoChapter] { playerState?.chapters ?? [] }
    private var storyboard: Storyboard? { playerState?.preferredStoryboard }

    var body: some View {
        PanelPageScrollView(config: scrollConfig) {
            LazyVStack(spacing: 0) {
                ForEach(chapters) { chapter in
                    ChapterRow(
                        chapter: chapter,
                        isActive: isChapterActive(chapter),
                        storyboard: storyboard,
                        showThumbnail: settings.effectiveShowThumbnails,
                        onTap: {
                            Task {
                                await playerService?.seek(to: chapter.startTime)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .task(id: context.video.id) {
            if settings.effectiveShowThumbnails {
                await preloadChapterSheets()
            }
        }
    }

    private func isChapterActive(_ chapter: VideoChapter) -> Bool {
        // Observes only chapter transitions, not per-tick currentTime updates.
        playerState?.activeChapterID == chapter.id
    }

    private func preloadChapterSheets() async {
        guard let storyboard else { return }
        let service = StoryboardService.shared
        for chapter in chapters {
            await service.loadSheet(for: chapter.startTime, from: storyboard)
        }
    }
}

#endif
