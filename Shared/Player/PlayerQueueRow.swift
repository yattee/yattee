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
            #if os(iOS)
                guard !item.video.localStreamIsDirectory else {
                    if let url = item.video?.localStream?.localURL {
                        withAnimation {
                            DocumentsModel.shared.goToURL(url)
                        }
                    }
                    return
                }
            #endif
            }

            if item.video.localStreamIsFile, let url = item.video.localStream?.localURL {
                URLBookmarkModel.shared.saveBookmark(url)
            }

            player.prepareCurrentItemForHistory()

            player.avPlayerBackend.startPictureInPictureOnPlay = player.playingInPictureInPicture

            player.videoBeingOpened = item.video

            let playItem = {
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
            VideoBanner(video: item.video, playbackTime: watchStoppedAt, videoDuration: watch?.videoDuration)
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
