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
            #if os(iOS)
                Button(action: {
                    self.expand.toggle() // Use your expanding logic here
                }) {
                    contents
                }
            #else
                contents
            #endif
        }
    }

    var contents: some View {
        Section {
            ForEach(chapters.prefix(3).indices, id: \.self) { index in
                ChapterView(chapter: chapters[index])
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
