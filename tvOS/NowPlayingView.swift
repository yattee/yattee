import CoreMedia
import Defaults
import SwiftUI

struct NowPlayingView: View {
    enum ViewSection: CaseIterable {
        case nowPlaying, playingNext, playedPreviously, related, comments, chapters
    }

    var sections = [ViewSection.nowPlaying, .playingNext, .playedPreviously, .related]
    var inInfoViewController = false

    @State private var repliesID: Comment.ID?

    @FetchRequest(sortDescriptors: [.init(key: "watchedAt", ascending: false)])
    var watches: FetchedResults<Watch>

    @EnvironmentObject<CommentsModel> private var comments
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<RecentsModel> private var recents

    @Default(.saveHistory) private var saveHistory
    @Default(.showHistoryInPlayer) private var showHistoryInPlayer

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
                            .onAppear {
                                player.loadQueueVideoDetails(item)
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

                if sections.contains(.playedPreviously), saveHistory, showHistoryInPlayer, !visibleWatches.isEmpty {
                    Section(header: Text("Played Previously")) {
                        ForEach(visibleWatches, id: \.videoID) { watch in
                            Button {
                                player.playHistory(
                                    PlayerQueueItem.from(watch, video: player.historyVideo(watch.videoID))
                                )
                                player.show()
                            } label: {
                                VideoBanner(
                                    video: player.historyVideo(watch.videoID),
                                    playbackTime: CMTime.secondsInDefaultTimescale(watch.stoppedAt),
                                    videoDuration: watch.videoDuration
                                )
                            }
                            .onAppear {
                                player.loadHistoryVideoDetails(watch.videoID)
                            }
                            .contextMenu {
                                VideoContextMenuView(video: watch.video)
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
                        VStack(alignment: .center) {
                            PlaceholderProgressView()
                                .onAppear {
                                    comments.load()
                                }
                        }
                    } else {
                        Section {
                            ForEach(comments.all) { comment in
                                CommentView(comment: comment, repliesID: $repliesID)
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
                    }
                }

                if sections.contains(.chapters) {
                    if let video = player.currentVideo {
                        if video.chapters.isEmpty {
                            NoCommentsView(text: "No chapters information available".localized(), systemImage: "xmark.circle.fill")
                        } else {
                            Section(header: Text("Chapters")) {
                                ForEach(video.chapters) { chapter in
                                    ChapterView(chapter: chapter)
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
