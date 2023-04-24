import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct ChaptersView: View {
    @ObservedObject private var player = PlayerModel.shared

    var chapters: [Chapter] {
        player.videoForDisplay?.chapters ?? []
    }

    var chaptersHaveImages: Bool {
        chapters.allSatisfy { $0.image != nil }
    }

    var body: some View {
        if !chapters.isEmpty {
            #if os(tvOS)
                List {
                    Section {
                        ForEach(chapters) { chapter in
                            ChapterView(chapter: chapter)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            #else
                if chaptersHaveImages {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 20) {
                            ForEach(chapters) { chapter in
                                ChapterView(chapter: chapter)
                            }
                        }
                        .padding(.horizontal, 15)
                    }
                    .frame(minHeight: ChapterView.thumbnailHeight + 100)
                } else {
                    Section {
                        ForEach(chapters) { chapter in
                            ChapterView(chapter: chapter)
                        }
                    }
                    .padding(.horizontal)
                }
            #endif
        } else {
            NoCommentsView(text: "No chapters information available".localized(), systemImage: "xmark.circle.fill")
        }
    }
}

struct ChaptersView_Previews: PreviewProvider {
    static var previews: some View {
        ChaptersView()
            .injectFixtureEnvironmentObjects()
    }
}
