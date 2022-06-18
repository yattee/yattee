import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct ChaptersView: View {
    @EnvironmentObject<PlayerModel> private var player

    var body: some View {
        List {
            if let chapters = player.currentVideo?.chapters, !chapters.isEmpty {
                Section(header: Text("Chapters")) {
                    ForEach(chapters) { chapter in
                        Button {
                            player.backend.seek(to: chapter.start)
                        } label: {
                            chapterButtonLabel(chapter)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text(player.currentVideo?.title ?? "")
            }
        }
        .id(UUID())
        #if os(macOS)
            .listStyle(.inset)
        #elseif os(iOS)
            .listStyle(.grouped)
        #else
            .listStyle(.plain)
        #endif
    }

    @ViewBuilder func chapterButtonLabel(_ chapter: Chapter) -> some View {
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

struct ChaptersView_Preview: PreviewProvider {
    static var previews: some View {
        ChaptersView()
            .injectFixtureEnvironmentObjects()
    }
}
