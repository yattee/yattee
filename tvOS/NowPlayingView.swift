import CoreMedia
import Defaults
import SwiftUI

struct NowPlayingView: View {
    enum ViewSection: CaseIterable {
        case nowPlaying, playingNext, related, comments, chapters
    }

    var sections = [ViewSection.nowPlaying, .playingNext, .related]
    var inInfoViewController = false

    @State private var repliesID: Comment.ID?
    @State private var availableWidth = 0.0

    @FetchRequest(sortDescriptors: [.init(key: "watchedAt", ascending: false)])
    var watches: FetchedResults<Watch>

    @ObservedObject private var comments = CommentsModel.shared
    @ObservedObject private var player = PlayerModel.shared

    @Default(.saveHistory) private var saveHistory

    var body: some View {
        if inInfoViewController {
            content
                .background(.thinMaterial)
                .mask(RoundedRectangle(cornerRadius: 24))
        } else {
            content
        }
    }

    var content: some View {
        List {
            Group {
                if sections.contains(.nowPlaying), let item = player.currentItem {
                    Section(header: Text("Now Playing")) {
                        Button {
                            player.show()
                        } label: {
                            VideoBanner(video: item.video)
                        }
                        .contextMenu {
                            Button("Close Video") {
                                player.closeCurrentItem()
                            }

                            Button("Cancel", role: .cancel) {}
                        }
                    }
                    .onPlayPauseCommand(perform: player.togglePlay)
                }

                if sections.contains(.playingNext) {
                    Section(header: Text("Playing Next")) {
                        if player.queue.isEmpty {
                            Text("Queue is empty")
                                .padding([.vertical, .leading], 40)
                                .foregroundColor(.secondary)
                        }

                        ForEach(player.queue) { item in
                            Button {
                                player.advanceToItem(item)
                                player.show()
                            } label: {
                                VideoBanner(video: item.video)
                            }
                            .contextMenu {
                                Button("Remove", role: .destructive) {
                                    player.remove(item)
                                }

                                Button("Remove All", role: .destructive) {
                                    player.removeQueueItems()
                                }
                            }
                        }
                    }
                }

                if sections.contains(.related), let video = player.currentVideo, !video.related.isEmpty {
                    Section(header: Text("Related")) {
                        ForEach(video.related) { video in
                            Button {
                                player.play(video)
                            } label: {
                                VideoBanner(video: video)
                            }
                            .contextMenu {
                                VideoContextMenuView(video: video)
                            }
                        }
                    }
                }

                if sections.contains(.comments) {
                    if comments.disabled {
                        NoCommentsView(text: "Comments are disabled".localized(), systemImage: "xmark.circle.fill")
                    } else if comments.loaded && comments.all.isEmpty {
                        NoCommentsView(text: "No comments".localized(), systemImage: "0.circle.fill")
                    } else if !comments.loaded {
                        VStack {
                            PlaceholderProgressView()
                                .onAppear {
                                    comments.loadIfNeeded()
                                }
                        }
                    } else {
                        Section {
                            ForEach(comments.all) { comment in
                                CommentView(comment: comment, repliesID: $repliesID, availableWidth: availableWidth)
                            }
                            if comments.nextPageAvailable {
                                Text("Scroll to load more...")
                                    .foregroundColor(.secondary)
                                    .padding(.leading)
                                    .onAppear {
                                        comments.loadNextPage()
                                    }
                            }
                        }
                        .background(GeometryReader { geometry in
                            Color.clear
                                .onAppear {
                                    self.availableWidth = Double(geometry.size.width)
                                }
                        })
                    }
                }

                if sections.contains(.chapters) {
                    if let video = player.currentVideo {
                        if video.chapters.isEmpty {
                            NoCommentsView(text: "No chapters information available".localized(), systemImage: "xmark.circle.fill")
                        } else {
                            Section(header: Text("Chapters")) {
                                ForEach(video.chapters) { chapter in
                                    ChapterViewTVOS(chapter: chapter)
                                        .padding(.horizontal, 40)
                                }
                            }
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 20))
            .padding(.vertical, 20)
        }
        .padding(.horizontal, inInfoViewController ? 40 : 0)
        .listStyle(.grouped)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity, alignment: .leading)
    }

    private var visibleWatches: [Watch] {
        watches.filter { $0.videoID != player.currentVideo?.videoID }
    }
}

struct NowPlayingView_Previews: PreviewProvider {
    static var previews: some View {
        NowPlayingView(sections: [.chapters])
            .injectFixtureEnvironmentObjects()

        NowPlayingView(inInfoViewController: true)
            .injectFixtureEnvironmentObjects()
    }
}
