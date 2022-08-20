import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct ChapterView: View {
    var chapter: Chapter

    @EnvironmentObject<PlayerModel> private var player

    var body: some View {
        Button {
            player.backend.seek(to: chapter.start)
        } label: {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder func smallImage(_ chapter: Chapter) -> some View {
        WebImage(url: chapter.image)
            .resizable()
            .placeholder {
                ProgressView()
            }
            .indicator(.activity)
        #if os(tvOS)
            .frame(width: thumbnailWidth, height: 140)
            .mask(RoundedRectangle(cornerRadius: 12))
        #else
            .frame(width: thumbnailWidth, height: 60)
            .mask(RoundedRectangle(cornerRadius: 6))
        #endif
    }

    private var thumbnailWidth: Double {
        #if os(tvOS)
            250
        #else
            100
        #endif
    }
}

struct ChapterView_Preview: PreviewProvider {
    static var previews: some View {
        ChapterView(chapter: .init(title: "Chapter", start: 30))
            .injectFixtureEnvironmentObjects()
    }
}
