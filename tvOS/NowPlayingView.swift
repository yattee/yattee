import Defaults
import SwiftUI

struct NowPlayingView: View {
    enum ViewSection: CaseIterable {
        case nowPlaying, playingNext, playedPreviously, related, comments
    }

    var sections = [ViewSection.nowPlaying, .playingNext, .playedPreviously, .related]
    var inInfoViewController = false

    @State private var repliesID: Comment.ID?

    @EnvironmentObject<CommentsModel> private var comments
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<RecentsModel> private var recents

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
                            player.presentPlayer()
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
                            Text("Playback queue is empty")
                                .padding([.vertical, .leading], 40)
                                .foregroundColor(.secondary)
                        }

                        ForEach(player.queue) { item in
                            Button {
                                player.advanceToItem(item)
                                player.presentPlayer()
                            } label: {
                                VideoBanner(video: item.video)
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    player.remove(item)
                                }
                            }
                        }
                    }
                }

                if sections.contains(.related), !player.currentVideo.isNil, !player.currentVideo!.related.isEmpty {
                    Section(header: inInfoViewController ? AnyView(EmptyView()) : AnyView(Text("Related"))) {
                        ForEach(player.currentVideo!.related) { video in
                            Button {
                                player.playNow(video)
                                player.presentPlayer()
                            } label: {
                                VideoBanner(video: video)
                            }
                            .contextMenu {
                                Button("Play Next") {
                                    player.playNext(video)
                                }
                                Button("Play Last") {
                                    player.enqueueVideo(video)
                                }
                                Button("Cancel", role: .cancel) {}
                            }
                        }
                    }
                }

                if sections.contains(.playedPreviously), saveHistory, !player.history.isEmpty {
                    Section(header: Text("Played Previously")) {
                        ForEach(player.history) { item in
                            Button {
                                player.playHistory(item)
                                player.presentPlayer()
                            } label: {
                                VideoBanner(video: item.video, playbackTime: item.playbackTime, videoDuration: item.videoDuration)
                            }
                            .contextMenu {
                                Button("Remove", role: .destructive) {
                                    player.removeHistory(item)
                                }

                                Button("Remove All", role: .destructive) {
                                    player.removeHistoryItems()
                                }
                            }
                        }
                    }
                }

                if sections.contains(.comments) {
                    if !comments.loaded {
                        VStack(alignment: .center) {
                            progressView
                                .onAppear {
                                    comments.load()
                                }
                        }
                    } else {
                        Section {
                            ForEach(comments.all) { comment in
                                CommentView(comment: comment, repliesID: $repliesID)
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

    func header(_ text: String) -> some View {
        Text(text)
            .font((inInfoViewController ? Font.system(size: 40) : .title3).bold())
            .foregroundColor(.secondary)
    }

    private var progressView: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            Spacer()
        }
    }
}

struct NowPlayingView_Previews: PreviewProvider {
    static var previews: some View {
        NowPlayingView()
            .injectFixtureEnvironmentObjects()

        NowPlayingView(inInfoViewController: true)
            .injectFixtureEnvironmentObjects()
    }
}
