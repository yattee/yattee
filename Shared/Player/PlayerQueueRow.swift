import Foundation
import SwiftUI

struct PlayerQueueRow: View {
    let item: PlayerQueueItem
    var history = false
    @Binding var fullScreen: Bool

    @EnvironmentObject<PlayerModel> private var player

    var body: some View {
        Group {
            Button {
                player.addCurrentItemToHistory()

                if history {
                    let newItem = player.enqueueVideo(item.video, prepending: true)
                    player.advanceToItem(newItem!)
                    if let historyItemIndex = player.history.firstIndex(of: item) {
                        player.history.remove(at: historyItemIndex)
                    }
                } else {
                    player.advanceToItem(item)
                }

                if fullScreen {
                    withAnimation {
                        fullScreen = false
                    }
                }
            } label: {
                VideoBanner(video: item.video)
            }
            .buttonStyle(.plain)
        }
    }
}
