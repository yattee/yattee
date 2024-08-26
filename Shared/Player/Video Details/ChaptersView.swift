import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct ChaptersView: View {
    @ObservedObject private var player = PlayerModel.shared
    @Binding var expand: Bool
    let chaptersHaveImages: Bool
    let showThumbnails: Bool

    var chapters: [Chapter] {
        player.videoForDisplay?.chapters ?? []
    }

    var body: some View {
        if !chapters.isEmpty {
            if chaptersHaveImages, showThumbnails {
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
                        ScrollViewReader { scrollViewProxy in
                            LazyHStack(spacing: 20) {
                                chapterViews(for: chapters[...])
                            }
                            .padding(.horizontal, 15)
                            .onAppear {
                                scrollToCurrentChapter(scrollViewProxy)
                            }
                            .onChange(of: player.currentChapterIndex) { _ in
                                scrollToCurrentChapter(scrollViewProxy)
                            }
                        }
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
                    Section { chapterViews(for: chapters[...]) }
                        .padding(.horizontal)
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
                ChapterView(chapter: chapter, chapterIndex: index, showThumbnail: showThumbnails)
                    .id(index)
                    .opacity(index == 0 ? 1.0 : opacity)
                    .allowsHitTesting(clickable)
            }
        }

        private func scrollToCurrentChapter(_ scrollViewProxy: ScrollViewProxy) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { // Slight delay to ensure the view is fully rendered
                if let currentChapterIndex = player.currentChapterIndex {
                    scrollViewProxy.scrollTo(currentChapterIndex, anchor: .center)
                }
            }
        }
    #endif
}

struct ChaptersView_Previews: PreviewProvider {
    static var previews: some View {
        ChaptersView(expand: .constant(false), chaptersHaveImages: false, showThumbnails: true)
            .injectFixtureEnvironmentObjects()
    }
}
