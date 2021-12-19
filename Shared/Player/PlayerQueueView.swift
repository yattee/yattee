import Defaults
import Foundation
import SwiftUI

struct PlayerQueueView: View {
    @Binding var sidebarQueue: Bool
    @Binding var fullScreen: Bool

    @EnvironmentObject<PlayerModel> private var player

    @Default(.saveHistory) private var saveHistory

    var body: some View {
        List {
            Group {
                playingNext
                if sidebarQueue {
                    related
                }
                if saveHistory {
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
                    .contextMenu {
                        removeButton(item, history: false)
                        removeAllButton(history: false)
                    }
            }
        }
    }

    var playedPreviously: some View {
        Group {
            if !player.history.isEmpty {
                Section(header: Text("Played Previously")) {
                    ForEach(player.history) { item in
                        PlayerQueueRow(item: item, history: true, fullScreen: $fullScreen)
                            .contextMenu {
                                removeButton(item, history: true)
                                removeAllButton(history: true)
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

    private func removeButton(_ item: PlayerQueueItem, history: Bool) -> some View {
        Button {
            removeButtonAction(item, history: history)
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    private func removeButtonAction(_ item: PlayerQueueItem, history: Bool) {
        _ = history ? player.removeHistory(item) : player.remove(item)
    }

    private func removeAllButton(history: Bool) -> some View {
        Button {
            removeAllButtonAction(history: history)
        } label: {
            Label("Remove All", systemImage: "trash.fill")
        }
    }

    private func removeAllButtonAction(history: Bool) {
        _ = history ? player.removeHistoryItems() : player.removeQueueItems()
    }
}

struct PlayerQueueView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            PlayerQueueView(sidebarQueue: .constant(true), fullScreen: .constant(true))
        }
        .injectFixtureEnvironmentObjects()
    }
}
