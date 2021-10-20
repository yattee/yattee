import Foundation
import SwiftUI

struct PlayerQueueView: View {
    @Binding var fullScreen: Bool

    @EnvironmentObject<PlayerModel> private var player

    var body: some View {
        List {
            playingNext
            playedPreviously
        }

        #if os(macOS)
            .listStyle(.inset)
        #elseif os(iOS)
            .listStyle(.insetGrouped)
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
        Section(header: Text("Played Previously")) {
            if player.history.isEmpty {
                Text("History is empty")
                    .foregroundColor(.secondary)
            }

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

    func removeButton(_ item: PlayerQueueItem, history: Bool) -> some View {
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

    func removeAllButton(history: Bool) -> some View {
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
            PlayerQueueView(fullScreen: .constant(true))
        }
        .injectFixtureEnvironmentObjects()
    }
}
