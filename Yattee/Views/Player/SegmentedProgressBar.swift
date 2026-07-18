//
//  SegmentedProgressBar.swift
//  Yattee
//
//  Progress bar with visual chapter segments separated by gaps,
//  and optional SponsorBlock segment overlays.
//

import SwiftUI

/// A progress bar that displays chapter boundaries as visual segments with gaps.
/// When no chapters are available, renders as a single continuous bar.
/// Optionally displays SponsorBlock segments as colored overlays.
struct SegmentedProgressBar: View {
    let chapters: [VideoChapter]
    let duration: TimeInterval
    let currentTime: TimeInterval
    let bufferedTime: TimeInterval
    let height: CGFloat
    let gapWidth: CGFloat
    let playedColor: Color
    let bufferedColor: Color
    let backgroundColor: Color

    /// SponsorBlock segments to display on the progress bar.
    var sponsorSegments: [SponsorBlockSegment] = []

    /// Settings for SponsorBlock segment display.
    var sponsorBlockSettings: SponsorBlockSegmentSettings = .default

    /// Progress as a fraction (0-1).
    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    /// Buffered progress as a fraction (0-1).
    private var bufferedProgress: Double {
        guard duration > 0 else { return 0 }
        return min(bufferedTime / duration, 1)
    }

    /// Filtered sponsor segments that should be displayed.
    private var visibleSponsorSegments: [SponsorBlockSegment] {
        guard sponsorBlockSettings.showSegments else { return [] }
        return sponsorSegments.filter { segment in
            sponsorBlockSettings.settings(for: segment.category).isVisible
        }
    }

    var body: some View {
        GeometryReader { geometry in
            if chapters.count >= 2 {
                segmentedBar(geometry: geometry)
            } else {
                singleBar(geometry: geometry)
            }
        }
        .frame(height: height)
    }

    // MARK: - Single Bar (No Chapters)

    @ViewBuilder
    private func singleBar(geometry: GeometryProxy) -> some View {
        ZStack(alignment: .leading) {
            // Background
            Rectangle()
                .fill(backgroundColor)

            // Buffered
            Rectangle()
                .fill(bufferedColor)
                .frame(width: geometry.size.width * bufferedProgress)

            // Played
            Rectangle()
                .fill(playedColor)
                .frame(width: geometry.size.width * progress)

            // SponsorBlock segments (on top)
            sponsorSegmentsOverlay(
                totalWidth: geometry.size.width,
                rangeStart: 0,
                rangeEnd: duration
            )
        }
    }

    // MARK: - Segmented Bar (With Chapters)

    @ViewBuilder
    private func segmentedBar(geometry: GeometryProxy) -> some View {
        let totalGapWidth = CGFloat(chapters.count - 1) * gapWidth
        let availableWidth = geometry.size.width - totalGapWidth

        HStack(spacing: gapWidth) {
            ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                let segmentWidth = segmentWidth(for: chapter, index: index, availableWidth: availableWidth)
                let chapterEnd = nextChapterStart(after: index)

                ChapterSegmentView(
                    chapter: chapter,
                    nextChapterStart: chapterEnd,
                    duration: duration,
                    currentTime: currentTime,
                    bufferedTime: bufferedTime,
                    segmentWidth: segmentWidth,
                    playedColor: playedColor,
                    bufferedColor: bufferedColor,
                    backgroundColor: backgroundColor,
                    sponsorSegments: segmentsInRange(start: chapter.startTime, end: chapterEnd),
                    sponsorBlockSettings: sponsorBlockSettings
                )
                .frame(width: segmentWidth, height: height)
            }
        }
    }

    // MARK: - Sponsor Segments Overlay

    @ViewBuilder
    private func sponsorSegmentsOverlay(
        totalWidth: CGFloat,
        rangeStart: TimeInterval,
        rangeEnd: TimeInterval
    ) -> some View {
        let rangeDuration = rangeEnd - rangeStart

        ForEach(visibleSponsorSegments, id: \.uuid) { segment in
            if rangeDuration > 0 {
                let segmentStart = max(segment.startTime, rangeStart)
                let segmentEnd = min(segment.endTime, rangeEnd)

                // Only render if segment overlaps with range
                if segmentStart < segmentEnd {
                    let startFraction = (segmentStart - rangeStart) / rangeDuration
                    let endFraction = (segmentEnd - rangeStart) / rangeDuration
                    let segmentWidthFraction = endFraction - startFraction

                    let categorySettings = sponsorBlockSettings.settings(for: segment.category)

                    Rectangle()
                        .fill(categorySettings.color.color)
                        .frame(width: totalWidth * segmentWidthFraction)
                        .offset(x: totalWidth * startFraction)
                }
            }
        }
    }

    // MARK: - Helpers

    private func segmentWidth(for chapter: VideoChapter, index: Int, availableWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }

        let chapterEnd = nextChapterStart(after: index)
        let chapterDuration = chapterEnd - chapter.startTime
        let proportion = chapterDuration / duration

        return max(1, availableWidth * proportion) // Minimum 1pt width
    }

    private func nextChapterStart(after index: Int) -> TimeInterval {
        if index < chapters.count - 1 {
            return chapters[index + 1].startTime
        }
        return duration
    }

    /// Returns sponsor segments that overlap with the given time range.
    private func segmentsInRange(start: TimeInterval, end: TimeInterval) -> [SponsorBlockSegment] {
        visibleSponsorSegments.filter { segment in
            segment.startTime < end && segment.endTime > start
        }
    }
}

// MARK: - Chapter Segment View

/// A single chapter segment within the progress bar.
private struct ChapterSegmentView: View {
    let chapter: VideoChapter
    let nextChapterStart: TimeInterval
    let duration: TimeInterval
    let currentTime: TimeInterval
    let bufferedTime: TimeInterval
    let segmentWidth: CGFloat
    let playedColor: Color
    let bufferedColor: Color
    let backgroundColor: Color
    let sponsorSegments: [SponsorBlockSegment]
    let sponsorBlockSettings: SponsorBlockSegmentSettings

    /// How much of this chapter has been played (0-1).
    private var playedProgress: Double {
        let chapterDuration = nextChapterStart - chapter.startTime
        guard chapterDuration > 0 else { return 0 }

        if currentTime <= chapter.startTime {
            return 0
        } else if currentTime >= nextChapterStart {
            return 1
        } else {
            return (currentTime - chapter.startTime) / chapterDuration
        }
    }

    /// How much of this chapter has been buffered (0-1).
    private var bufferedProgress: Double {
        let chapterDuration = nextChapterStart - chapter.startTime
        guard chapterDuration > 0 else { return 0 }

        if bufferedTime <= chapter.startTime {
            return 0
        } else if bufferedTime >= nextChapterStart {
            return 1
        } else {
            return (bufferedTime - chapter.startTime) / chapterDuration
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(backgroundColor)

                // Buffered
                Rectangle()
                    .fill(bufferedColor)
                    .frame(width: geometry.size.width * bufferedProgress)

                // Played
                Rectangle()
                    .fill(playedColor)
                    .frame(width: geometry.size.width * playedProgress)

                // SponsorBlock segments (on top)
                sponsorSegmentsOverlay(geometry: geometry)
            }
        }
    }

    @ViewBuilder
    private func sponsorSegmentsOverlay(geometry: GeometryProxy) -> some View {
        let chapterDuration = nextChapterStart - chapter.startTime

        ForEach(sponsorSegments, id: \.uuid) { segment in
            if chapterDuration > 0 {
                let segmentStart = max(segment.startTime, chapter.startTime)
                let segmentEnd = min(segment.endTime, nextChapterStart)

                if segmentStart < segmentEnd {
                    let startFraction = (segmentStart - chapter.startTime) / chapterDuration
                    let endFraction = (segmentEnd - chapter.startTime) / chapterDuration
                    let segmentWidthFraction = endFraction - startFraction

                    let categorySettings = sponsorBlockSettings.settings(for: segment.category)

                    Rectangle()
                        .fill(categorySettings.color.color)
                        .frame(width: geometry.size.width * segmentWidthFraction)
                        .offset(x: geometry.size.width * startFraction)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("With Chapters") {
    VStack(spacing: 20) {
        SegmentedProgressBar(
            chapters: [
                VideoChapter(title: "Intro", startTime: 0, endTime: 60),
                VideoChapter(title: "Topic A", startTime: 60, endTime: 180),
                VideoChapter(title: "Topic B", startTime: 180, endTime: 400),
                VideoChapter(title: "Outro", startTime: 400, endTime: 600),
            ],
            duration: 600,
            currentTime: 150,
            bufferedTime: 300,
            height: 4,
            gapWidth: 2,
            playedColor: .red,
            bufferedColor: .white.opacity(0.5),
            backgroundColor: .white.opacity(0.3)
        )
        .frame(width: 300)

        SegmentedProgressBar(
            chapters: [],
            duration: 600,
            currentTime: 150,
            bufferedTime: 300,
            height: 4,
            gapWidth: 2,
            playedColor: .red,
            bufferedColor: .white.opacity(0.5),
            backgroundColor: .white.opacity(0.3)
        )
        .frame(width: 300)
    }
    .padding()
    .background(Color.black)
}

#Preview("With SponsorBlock Segments") {
    VStack(spacing: 20) {
        // Single bar with sponsor segments
        SegmentedProgressBar(
            chapters: [],
            duration: 600,
            currentTime: 150,
            bufferedTime: 300,
            height: 4,
            gapWidth: 2,
            playedColor: .red,
            bufferedColor: .white.opacity(0.5),
            backgroundColor: .white.opacity(0.3),
            sponsorSegments: [
                SponsorBlockSegment(
                    uuid: "1",
                    category: .sponsor,
                    actionType: .skip,
                    segment: [30.0, 90.0],
                    videoDuration: 600,
                    locked: nil,
                    votes: nil,
                    segmentDescription: nil
                ),
                SponsorBlockSegment(
                    uuid: "2",
                    category: .intro,
                    actionType: .skip,
                    segment: [0.0, 15.0],
                    videoDuration: 600,
                    locked: nil,
                    votes: nil,
                    segmentDescription: nil
                ),
            ],
            sponsorBlockSettings: .default
        )
        .frame(width: 300)

        // Segmented bar with sponsor segments
        SegmentedProgressBar(
            chapters: [
                VideoChapter(title: "Intro", startTime: 0, endTime: 60),
                VideoChapter(title: "Topic A", startTime: 60, endTime: 180),
                VideoChapter(title: "Topic B", startTime: 180, endTime: 400),
                VideoChapter(title: "Outro", startTime: 400, endTime: 600),
            ],
            duration: 600,
            currentTime: 150,
            bufferedTime: 300,
            height: 4,
            gapWidth: 2,
            playedColor: .red,
            bufferedColor: .white.opacity(0.5),
            backgroundColor: .white.opacity(0.3),
            sponsorSegments: [
                SponsorBlockSegment(
                    uuid: "1",
                    category: .sponsor,
                    actionType: .skip,
                    segment: [30.0, 90.0],
                    videoDuration: 600,
                    locked: nil,
                    votes: nil,
                    segmentDescription: nil
                ),
                SponsorBlockSegment(
                    uuid: "2",
                    category: .outro,
                    actionType: .skip,
                    segment: [500.0, 600.0],
                    videoDuration: 600,
                    locked: nil,
                    votes: nil,
                    segmentDescription: nil
                ),
            ],
            sponsorBlockSettings: .default
        )
        .frame(width: 300)
    }
    .padding()
    .background(Color.black)
}
