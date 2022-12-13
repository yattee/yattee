import CoreMedia
import Defaults
import Foundation
import SwiftUI

struct PlayerQueueRow: View {
    let item: PlayerQueueItem
    var history = false
    var autoplay = false

    private var player = PlayerModel.shared

    @Default(.closePiPOnNavigation) var closePiPOnNavigation

    @FetchRequest private var watchRequest: FetchedResults<Watch>

    init(item: PlayerQueueItem, history: Bool = false, autoplay: Bool = false) {
        self.item = item
        self.history = history
        self.autoplay = autoplay
        _watchRequest = FetchRequest<Watch>(
            entity: Watch.entity(),
            sortDescriptors: [],
            predicate: NSPredicate(format: "videoID = %@", item.videoID)
        )
    }

    var body: some View {
        Button {
            guard let video = item.video else { return }
            guard video != player.currentVideo else {
                player.show()
                return
            }

            #if os(iOS)
                guard !video.localStreamIsDirectory else {
                    if let url = video.localStream?.localURL {
                        withAnimation {
                            DocumentsModel.shared.goToURL(url)
                        }
                    }
                    return
                }
            #endif

            if video.localStreamIsFile, let url = video.localStream?.localURL {
                URLBookmarkModel.shared.saveBookmark(url)
            }

            player.prepareCurrentItemForHistory()

            player.avPlayerBackend.startPictureInPictureOnPlay = player.playingInPictureInPicture

            player.videoBeingOpened = video

            let playItem = {
                if history {
                    player.playHistory(item, at: watchStoppedAt)
                } else {
                    player.advanceToItem(item, at: watchStoppedAt)
                }

                if closePiPOnNavigation, player.playingInPictureInPicture {
                    player.closePiP()
                }

                if autoplay {
                    player.resetAutoplay()
                }
            }

            #if os(iOS)
                if player.presentingPlayer {
                    playItem()
                } else {
                    player.onPresentPlayer.append(playItem)
                }
            #else
                playItem()
            #endif

            player.show()
        } label: {
            VideoBanner(video: item.video, playbackTime: watchStoppedAt, videoDuration: watch?.videoDuration, watch: watch)
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
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
