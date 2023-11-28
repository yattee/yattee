import CoreMedia
import Foundation
import SDWebImageSwiftUI
import SwiftUI

#if !os(tvOS)
    struct ChapterView: View {
        var chapter: Chapter
        var nextChapterStart: Double?

        var chapterIndex: Int
        @ObservedObject private var player = PlayerModel.shared

        var isCurrentChapter: Bool {
            player.currentChapterIndex == chapterIndex
        }

        var hasBeenPlayed: Bool {
            player.playedChapters.contains(chapterIndex)
        }

        var body: some View {
            Button(action: {
                player.backend.seek(to: chapter.start, seekType: .userInteracted)
            }) {
                Group {
                    verticalChapter
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onReceive(PlayerTimeModel.shared.$currentTime) { cmTime in
                let time = CMTimeGetSeconds(cmTime)
                if time >= self.chapter.start, self.nextChapterStart == nil || time < self.nextChapterStart! {
                    player.currentChapterIndex = self.chapterIndex
                    if !player.playedChapters.contains(self.chapterIndex) {
                        player.playedChapters.append(self.chapterIndex)
                    }
                }
            }
        }

        var verticalChapter: some View {
            VStack(spacing: 12) {
                if !chapter.image.isNil {
                    smallImage(chapter)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(chapter.title)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .font(.headline)
                        .foregroundColor(isCurrentChapter ? .appRed : .primary)
                    Text(chapter.start.formattedAsPlaybackTime(allowZero: true) ?? "")
                        .font(.system(.subheadline).monospacedDigit())
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: !chapter.image.isNil ? Self.thumbnailWidth : nil, alignment: .leading)
            }
        }

        @ViewBuilder func smallImage(_ chapter: Chapter) -> some View {
            WebImage(url: chapter.image, options: [.lowPriority])
                .resizable()
                .placeholder {
                    ProgressView()
                }
                .indicator(.activity)
                .frame(width: Self.thumbnailWidth, height: Self.thumbnailHeight)

                .mask(RoundedRectangle(cornerRadius: 6))
        }

        static var thumbnailWidth: Double {
            250
        }

        static var thumbnailHeight: Double {
            thumbnailWidth / 1.7777
        }
    }

#else
    struct ChapterViewTVOS: View {
        var chapter: Chapter
        var player = PlayerModel.shared

        var body: some View {
            Button {
                player.backend.seek(to: chapter.start, seekType: .userInteracted)
            } label: {
                Group {
                    horizontalChapter
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        var horizontalChapter: some View {
            HStack(spacing: 12) {
                if !chapter.image.isNil {
                    smallImage(chapter)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(chapter.title)
                        .font(.headline)
                    Text(chapter.start.formattedAsPlaybackTime(allowZero: true) ?? "")
                        .font(.system(.subheadline).monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        @ViewBuilder func smallImage(_ chapter: Chapter) -> some View {
            WebImage(url: chapter.image, options: [.lowPriority])
                .resizable()
                .placeholder {
                    ProgressView()
                }
                .indicator(.activity)
                .frame(width: Self.thumbnailWidth, height: Self.thumbnailHeight)
                .mask(RoundedRectangle(cornerRadius: 12))
        }

        static var thumbnailWidth: Double {
            250
        }

        static var thumbnailHeight: Double {
            thumbnailWidth / 1.7777
        }
    }
#endif

struct ChapterView_Preview: PreviewProvider {
    static var previews: some View {
        #if os(tvOS)
            ChapterViewTVOS(chapter: .init(title: "Chapter", start: 30))
                .injectFixtureEnvironmentObjects()
        #else
            ChapterView(chapter: .init(title: "Chapter", start: 30), nextChapterStart: nil, chapterIndex: 0)
                .injectFixtureEnvironmentObjects()
        #endif
    }
}
