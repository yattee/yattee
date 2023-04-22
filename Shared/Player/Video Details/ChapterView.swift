import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct ChapterView: View {
    var chapter: Chapter

    var player = PlayerModel.shared

    var body: some View {
        Button {
            player.backend.seek(to: chapter.start, seekType: .userInteracted)
        } label: {
            Group {
                #if os(tvOS)
                    horizontalChapter
                #else
                    verticalChapter
                #endif
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    #if os(tvOS)

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
    #else
        var verticalChapter: some View {
            VStack(spacing: 12) {
                if !chapter.image.isNil {
                    smallImage(chapter)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(chapter.title)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .font(.headline)
                    Text(chapter.start.formattedAsPlaybackTime(allowZero: true) ?? "")
                        .font(.system(.subheadline).monospacedDigit())
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: Self.thumbnailWidth, alignment: .leading)
            }
        }
    #endif

    @ViewBuilder func smallImage(_ chapter: Chapter) -> some View {
        WebImage(url: chapter.image, options: [.lowPriority])
            .resizable()
            .placeholder {
                ProgressView()
            }
            .indicator(.activity)
            .frame(width: Self.thumbnailWidth, height: Self.thumbnailHeight)
        #if os(tvOS)
            .mask(RoundedRectangle(cornerRadius: 12))
        #else
            .mask(RoundedRectangle(cornerRadius: 6))
        #endif
    }

    static var thumbnailWidth: Double {
        250
    }

    static var thumbnailHeight: Double {
        thumbnailWidth / 1.7777
    }
}

struct ChapterView_Preview: PreviewProvider {
    static var previews: some View {
        ChapterView(chapter: .init(title: "Chapter", start: 30))
            .injectFixtureEnvironmentObjects()
    }
}
