import Defaults
import Foundation
import SwiftUI

struct PlayerQueueView: View {
    var sidebarQueue: Bool
    @Binding var fullScreen: Bool

    @FetchRequest(sortDescriptors: [.init(key: "watchedAt", ascending: false)])
    var watches: FetchedResults<Watch>

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<PlayerModel> private var player

    @Default(.saveHistory) private var saveHistory
    @Default(.showHistoryInPlayer) private var showHistoryInPlayer

    var body: some View {
        List {
            Group {
                playingNext
                if sidebarQueue {
                    related
                }
                if saveHistory, showHistoryInPlayer {
                    playedPreviously
                }
            }
            #if !os(iOS)
            .padding(.vertical, 5)
            .listRowInsets(EdgeInsets())
            #endif
        }

        #if os(macOS)
        .listStyle(.inset)
        #elseif os(iOS)
        .listStyle(.grouped)
        #else
        .listStyle(.plain)
        #endif
    }

    var playingNext: some View {
        Section(header: Text("Playing Next")) {
            if player.queue.isEmpty {
                Text("Playback queue is empty")
                    .foregroundColor(.secondary)
            }

            ForEach(player.queue) { item in
                PlayerQueueRow(item: item, fullScreen: $fullScreen)
                    .onAppear {
                        player.loadQueueVideoDetails(item)
                    }
                    .contextMenu {
                        removeButton(item)
                        removeAllButton()
                    }
            }
        }
    }

    private var visibleWatches: [Watch] {
        watches.filter { $0.videoID != player.currentVideo?.videoID }
    }

    var playedPreviously: some View {
        Group {
            if !visibleWatches.isEmpty {
                Section(header: Text("Played Previously")) {
                    ForEach(visibleWatches, id: \.videoID) { watch in
                        PlayerQueueRow(
                            item: PlayerQueueItem.from(watch, video: player.historyVideo(watch.videoID)),
                            history: true,
                            fullScreen: $fullScreen
                        )
                        .onAppear {
                            player.loadHistoryVideoDetails(watch.videoID)
                        }
                        .contextMenu {
                            removeHistoryButton(watch)
                        }
                    }
                }
            }
        }
    }

    private var related: some View {
        Group {
            if !player.currentVideo.isNil, !player.currentVideo!.related.isEmpty {
                Section(header: Text("Related")) {
                    ForEach(player.currentVideo!.related) { video in
                        PlayerQueueRow(item: PlayerQueueItem(video), fullScreen: $fullScreen)
                            .contextMenu {
                                Button {
                                    player.playNext(video)
                                } label: {
                                    Label("Play Next", systemImage: "text.insert")
                                }

                                Button {
                                    player.enqueueVideo(video)
                                } label: {
                                    Label("Play Last", systemImage: "text.append")
                                }
                            }
                    }
                }
            }
        }
    }

    private func removeButton(_ item: PlayerQueueItem) -> some View {
        Button {
            player.remove(item)
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    private func removeAllButton() -> some View {
        Button {
            player.removeQueueItems()
        } label: {
            Label("Remove All", systemImage: "trash.fill")
        }
    }

    private func removeHistoryButton(_ watch: Watch) -> some View {
        Button {
            player.removeWatch(watch)
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }
}

struct PlayerQueueView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            PlayerQueueView(sidebarQueue: true, fullScreen: .constant(true))
        }
        .injectFixtureEnvironmentObjects()
    }
}
