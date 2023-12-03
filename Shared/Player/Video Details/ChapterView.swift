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
            player.currentChapter == chapterIndex
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
            .onReceive(
                NotificationCenter.default
                    .publisher(for: .getTimeUpdatesNotification)
                    .receive(on: DispatchQueue.main)
            ) { notification in
                if let cmTime = notification.object as? CMTime {
                    self.handleTimeUpdate(cmTime)
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
                        .foregroundColor(isCurrentChapter ? Color("AppRedColor") : .primary)
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

        private func handleTimeUpdate(_ cmTime: CMTime) {
            let time = CMTimeGetSeconds(cmTime)
            if time >= chapter.start, nextChapterStart == nil || time < nextChapterStart! {
                player.currentChapter = chapterIndex
            }
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
