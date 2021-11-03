import Foundation
import SwiftUI

struct PlayerQueueView: View {
    @Binding var sidebarQueue: Bool
    @Binding var fullScreen: Bool

    @EnvironmentObject<PlayerModel> private var player

    var body: some View {
        List {
            Group {
                playingNext
                if sidebarQueue {
                    related
                }
                playedPreviously
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
                #if os(iOS)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        removeButton(item, history: false)
                    }
                #endif
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
                        #if os(iOS)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                removeButton(item, history: true)
                            }
                        #endif
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
                                Button("Play Next") {
                                    player.playNext(video)
                                }
                                Button("Play Last") {
                                    player.enqueueVideo(video)
                                }
                            }
                    }
                }
            }
        }
    }

    private func removeButton(_ item: PlayerQueueItem, history: Bool) -> some View {
        Button(role: .destructive) {
            if history {
                player.removeHistory(item)
            } else {
                player.remove(item)
            }
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    private func removeAllButton(history: Bool) -> some View {
        Button(role: .destructive) {
            if history {
                player.removeHistoryItems()
            } else {
                player.removeQueueItems()
            }
        } label: {
            Label("Remove All", systemImage: "trash.fill")
        }
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
