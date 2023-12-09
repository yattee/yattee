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
                                ChapterViewTVOS(chapter: chapter)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                #else
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 20) { chapterViews(for: chapters[...]) }.padding(.horizontal, 15)
                    }
                #endif
            } else if expand {
                #if os(tvOS)
                    Section {
                        ForEach(chapters) { chapter in
                            ChapterViewTVOS(chapter: chapter)
                        }
                    }
                #else
                    Section { chapterViews(for: chapters[...]) }.padding(.horizontal)
                #endif
            } else {
                #if os(iOS)
                    Button(action: {
                        self.expand.toggle()
                    }) {
                        Section {
                            chapterViews(for: chapters.prefix(3), opacity: 0.3, clickable: false)
                        }.padding(.horizontal)
                    }
                #elseif os(macOS)
                    Section {
                        chapterViews(for: chapters.prefix(3), opacity: 0.3, clickable: false)
                    }.padding(.horizontal)
                #else
                    Section {
                        ForEach(chapters) { chapter in
                            ChapterViewTVOS(chapter: chapter)
                        }
                    }
                #endif
            }
        }
    }

    #if !os(tvOS)
        private func chapterViews(for chaptersToShow: ArraySlice<Chapter>, opacity: Double = 1.0, clickable: Bool = true) -> some View {
            ForEach(Array(chaptersToShow.indices), id: \.self) { index in
                let chapter = chaptersToShow[index]
                ChapterView(chapter: chapter, chapterIndex: index)
                    .opacity(index == 0 ? 1.0 : opacity)
                    .allowsHitTesting(clickable)
            }
        }
    #endif
}

struct ChaptersView_Previews: PreviewProvider {
    static var previews: some View {
        ChaptersView(expand: .constant(false))
            .injectFixtureEnvironmentObjects()
    }
}
