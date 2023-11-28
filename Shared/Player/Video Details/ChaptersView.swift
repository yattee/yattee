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
        if !chapters.isEmpty {
            if chaptersHaveImages {
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
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 20) {
                            ForEach(Array(chapters.indices), id: \.self) { index in
                                let chapter = chapters[index]
                                let nextChapterStart: Double? = index < chapters.count - 1 ? chapters[index + 1].start : nil
                                ChapterView(chapter: chapter, nextChapterStart: nextChapterStart, chapterIndex: index)
                            }
                        }
                        .padding(.horizontal, 15)
                    }
                #endif
            } else if expand {
                Section {
                    ForEach(Array(chapters.indices), id: \.self) { index in
                        let chapter = chapters[index]
                        let nextChapterStart: Double? = index < chapters.count - 1 ? chapters[index + 1].start : nil
                        ChapterView(chapter: chapter, nextChapterStart: nextChapterStart, chapterIndex: index)
                    }
                }
                .padding(.horizontal)
            } else {
                #if os(iOS)
                    Button(action: {
                        self.expand.toggle()
                    }) {
                        contents
                    }
                #else
                    contents
                #endif
            }
        }
    }

    var contents: some View {
        Section {
            ForEach(Array(chapters.prefix(3).indices), id: \.self) { index in
                let chapter = chapters[index]
                let nextChapterStart: Double? = index < chapters.count - 1 ? chapters[index + 1].start : nil
                ChapterView(chapter: chapter, nextChapterStart: nextChapterStart, chapterIndex: index)
                    .allowsHitTesting(expand)
                    .opacity(index == 0 ? 1.0 : 0.3)
            }
        }
        .padding(.horizontal)
    }
}

struct ChaptersView_Previews: PreviewProvider {
    static var previews: some View {
        ChaptersView(expand: .constant(false))
            .injectFixtureEnvironmentObjects()
    }
}
