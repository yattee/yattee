import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct ChaptersView: View {
    @ObservedObject private var player = PlayerModel.shared
    @Binding var expand: Bool

    var chapters: [Chapter] {
        player.videoForDisplay?.chapters ?? []
    }

    var chaptersHaveImages: Bool {
        chapters.allSatisfy { $0.image != nil }
    }

    var body: some View {
        if expand && !chapters.isEmpty {
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
        } else if !chapters.isEmpty {
            Section {
                ChapterView(chapter: chapters[0])
                if chapters.count > 1 {
                    ChapterView(chapter: chapters[1])
                        .opacity(0.3)
                }
            }
            .padding(.horizontal)
        }
    }
}

struct ChaptersView_Previews: PreviewProvider {
    static var previews: some View {
        ChaptersView(expand: .constant(false))
            .injectFixtureEnvironmentObjects()
    }
}
