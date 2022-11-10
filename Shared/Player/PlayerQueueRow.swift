import CoreMedia
import Defaults
import Foundation
import SwiftUI

struct PlayerQueueRow: View {
    let item: PlayerQueueItem
    var history = false
    var autoplay = false
    @Binding var fullScreen: Bool

    @EnvironmentObject<PlayerModel> private var player

    @Default(.closePiPOnNavigation) var closePiPOnNavigation

    @FetchRequest private var watchRequest: FetchedResults<Watch>

    init(item: PlayerQueueItem, history: Bool = false, autoplay: Bool = false, fullScreen: Binding<Bool> = .constant(false)) {
        self.item = item
        self.history = history
        self.autoplay = autoplay
        _fullScreen = fullScreen
        _watchRequest = FetchRequest<Watch>(
            entity: Watch.entity(),
            sortDescriptors: [],
            predicate: NSPredicate(format: "videoID = %@", item.videoID)
        )
    }

    var body: some View {
        Button {
            player.prepareCurrentItemForHistory()

            player.avPlayerBackend.startPictureInPictureOnPlay = player.playingInPictureInPicture

            player.videoBeingOpened = item.video
            player.show()

            if history {
                player.playHistory(item, at: watchStoppedAt)
            } else {
                player.advanceToItem(item, at: watchStoppedAt)
            }

            if fullScreen {
                withAnimation {
                    fullScreen = false
                }
            }

            if closePiPOnNavigation, player.playingInPictureInPicture {
                player.closePiP()
            }

            if autoplay {
                player.resetAutoplay()
            }
        } label: {
            VideoBanner(video: item.video, playbackTime: watchStoppedAt, videoDuration: watch?.videoDuration)
        }
        .buttonStyle(.plain)
    }

    private var watch: Watch? {
        watchRequest.first
    }

    private var watchStoppedAt: CMTime? {
        guard let seconds = watch?.stoppedAt else {
            return nil
        }

        return .secondsInDefaultTimescale(seconds)
    }
}

struct PlayerQueueRow_Previews: PreviewProvider {
    static var previews: some View {
        PlayerQueueRow(item: .init(
            .local(URL(string: "https://apple.com")!)
        ))
    }
}
