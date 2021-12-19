import Defaults
import Foundation
import SwiftUI

struct PlayerQueueRow: View {
    let item: PlayerQueueItem
    var history = false
    @Binding var fullScreen: Bool

    @EnvironmentObject<PlayerModel> private var player

    @Default(.closePiPOnNavigation) var closePiPOnNavigation

    var body: some View {
        Group {
            Button {
                player.addCurrentItemToHistory()

                if history {
                    player.playHistory(item)
                } else {
                    player.advanceToItem(item)
                }

                if fullScreen {
                    withAnimation {
                        fullScreen = false
                    }
                }

                if closePiPOnNavigation, player.playingInPictureInPicture {
                    player.closePiP()
                }
            } label: {
                VideoBanner(video: item.video, playbackTime: item.playbackTime, videoDuration: item.videoDuration)
            }
            .buttonStyle(.plain)
        }
    }
}
