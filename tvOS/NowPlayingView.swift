import SwiftUI

struct NowPlayingView: View {
    var inInfoViewController = false

    @EnvironmentObject<PlayerModel> private var player

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
                if !inInfoViewController, let item = player.currentItem {
                    Section(header: Text("Now Playing")) {
                        Button {
                            player.presentPlayer()
                        } label: {
                            VideoBanner(video: item.video)
                        }
                    }
                    .onPlayPauseCommand(perform: player.togglePlay)
                }

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

                if !player.history.isEmpty {
                    Section(header: Text("Played Previously")) {
                        ForEach(player.history) { item in
                            Button {
                                player.playHistory(item)
                                player.presentPlayer()
                            } label: {
                                VideoBanner(video: item.video, playbackTime: item.playbackTime, videoDuration: item.videoDuration)
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    player.removeHistory(item)
                                }

                                Button("Delete History", role: .destructive) {
                                    player.removeHistoryItems()
                                }
                            }
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 20))
            .padding(.vertical, 20)
//            .padding(.horizontal, 40)
        }
        .padding(.horizontal, inInfoViewController ? 40 : 0)
        .listStyle(.grouped)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity, alignment: .leading)
    }

    func header(_ text: String) -> some View {
        Text(text)
            .font((inInfoViewController ? Font.system(size: 40) : .title3).bold())
            .foregroundColor(.secondary)
//            .padding(.leading, 40)
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
