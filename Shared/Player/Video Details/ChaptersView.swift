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
                                chapterViews(for: chapters[...], scrollViewProxy: scrollViewProxy)
                            }
                            .padding(.horizontal, 15)
                            .onAppear {
                                if let currentChapterIndex = player.currentChapterIndex {
                                    scrollViewProxy.scrollTo(currentChapterIndex, anchor: .center)
                                }
                            }
                            .onChange(of: player.currentChapterIndex) { currentChapterIndex in
                                if let index = currentChapterIndex {
                                    scrollViewProxy.scrollTo(index, anchor: .center)
                                }
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
        private func chapterViews(for chaptersToShow: ArraySlice<Chapter>, opacity: Double = 1.0, clickable: Bool = true, scrollViewProxy: ScrollViewProxy? = nil) -> some View {
            ForEach(Array(chaptersToShow.indices), id: \.self) { index in
                let chapter = chaptersToShow[index]
                ChapterView(chapter: chapter, chapterIndex: index, showThumbnail: showThumbnails)
                    .id(index)
                    .opacity(index == 0 ? 1.0 : opacity)
                    .allowsHitTesting(clickable)
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
