import SwiftUI

struct NowPlayingView: View {
    var infoViewController = false

    @EnvironmentObject<PlayerModel> private var player

    var body: some View {
        if infoViewController {
            content
                .background(.thinMaterial)
                .mask(RoundedRectangle(cornerRadius: 24))
        } else {
            content
        }
    }

    var content: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading) {
                if !infoViewController, let item = player.currentItem {
                    Group {
                        header("Now Playing")

                        Button {
                            player.presentPlayer()
                        } label: {
                            VideoBanner(video: item.video)
                        }
                    }
                    .onPlayPauseCommand(perform: player.togglePlay)

                    .padding(.bottom, 20)
                }

                header("Playing Next")

                if player.queue.isEmpty {
                    Spacer()

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

                header("Played Previously")

                if player.history.isEmpty {
                    Spacer()

                    Text("History is empty")
                        .padding([.vertical, .leading], 40)
                        .foregroundColor(.secondary)
                }

                ForEach(player.history) { item in
                    Button {
                        player.playHistory(item)
                        player.presentPlayer()
                    } label: {
                        VideoBanner(video: item.video)
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
            .padding(.vertical)
            .padding(.horizontal, 40)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 260, maxHeight: .infinity, alignment: .leading)
    }

    func header(_ text: String) -> some View {
        Text(text)
            .font(.title3.bold())
            .foregroundColor(.secondary)
            .padding(.leading, 40)
    }
}

struct NowPlayingView_Previews: PreviewProvider {
    static var previews: some View {
        NowPlayingView()
            .injectFixtureEnvironmentObjects()
    }
}
