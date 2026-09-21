//
//  TVDetailsPanelPages.swift
//  Yattee
//
//  Related videos and chapters pages for the tvOS player details panel.
//

#if os(tvOS)
import SwiftUI

// MARK: - Related Videos

/// Focus-based list of videos related to the current one. Selecting a video
/// plays it immediately and dismisses the panel.
struct TVRelatedPanelList: View {
    let video: Video?
    let onDidSelectVideo: () -> Void

    @Environment(\.appEnvironment) private var appEnvironment

    private var relatedVideos: [Video] { video?.relatedVideos ?? [] }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(relatedVideos) { relatedVideo in
                    TVRelatedVideoRow(video: relatedVideo) {
                        playVideo(relatedVideo)
                    }
                }
            }
            .padding(.vertical, 24)
        }
    }

    private func playVideo(_ video: Video) {
        guard let playerService = appEnvironment?.playerService else { return }
        Task {
            await playerService.play(video: video)
        }
        onDidSelectVideo()
    }
}

/// Focusable row for a related video: thumbnail, title, channel.
private struct TVRelatedVideoRow: View {
    let video: Video
    let onTap: () -> Void

    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                DeArrowVideoThumbnail(
                    video: video,
                    cornerRadius: 6,
                    duration: video.formattedDuration
                )
                .frame(width: 160, height: 90)

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.displayTitle(using: appEnvironment?.deArrowBrandingProvider))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)

                    Text(video.author.name)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TVCommentButtonStyle(hasReplies: false))
    }
}

// MARK: - Chapters

/// Focus-based chapter list; selecting a chapter seeks and keeps the panel
/// open so nearby chapters stay reachable.
struct TVChaptersPanelList: View {
    @Environment(\.appEnvironment) private var appEnvironment

    private var playerService: PlayerService? { appEnvironment?.playerService }
    private var playerState: PlayerState? { playerService?.state }

    private var chapters: [VideoChapter] { playerState?.chapters ?? [] }
    private var currentTime: TimeInterval { playerState?.currentTime ?? 0 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(chapters) { chapter in
                        TVChapterRow(
                            chapter: chapter,
                            isActive: isChapterActive(chapter),
                            onTap: {
                                Task {
                                    await playerService?.seek(to: chapter.startTime)
                                }
                            }
                        )
                        .id(chapter.id)
                    }
                }
                .padding(.vertical, 24)
            }
            .onAppear {
                if let active = chapters.first(where: { isChapterActive($0) }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo(active.id, anchor: .center)
                    }
                }
            }
        }
    }

    private func isChapterActive(_ chapter: VideoChapter) -> Bool {
        let nextChapter = chapters.first { $0.startTime > chapter.startTime }
        let endTime = nextChapter?.startTime ?? .infinity
        return currentTime >= chapter.startTime && currentTime < endTime
    }
}

/// Focusable row for a chapter: title, start time, and an active indicator.
private struct TVChapterRow: View {
    let chapter: VideoChapter
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Text(chapter.formattedStartTime)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.6)))
                    .frame(width: 110, alignment: .leading)

                Text(chapter.title)
                    .font(.subheadline)
                    .fontWeight(isActive ? .semibold : .regular)
                    .lineLimit(2)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)

                Spacer()

                if isActive {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(TVCommentButtonStyle(hasReplies: false))
    }
}

#endif
