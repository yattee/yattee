import AVKit
import Foundation

final class PiPDelegate: NSObject, AVPictureInPictureControllerDelegate {
    var player: PlayerModel!

    func pictureInPictureController(
        _: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        print(error.localizedDescription)
    }

    func pictureInPictureControllerWillStartPictureInPicture(_: AVPictureInPictureController) {}

    func pictureInPictureControllerDidStartPictureInPicture(_: AVPictureInPictureController) {
        player?.playingInPictureInPicture = true
        player?.avPlayerBackend.startPictureInPictureOnPlay = false
    }

    func pictureInPictureControllerDidStopPictureInPicture(_: AVPictureInPictureController) {
        guard let player = player else {
            return
        }

        if player.avPlayerBackend.switchToMPVOnPipClose,
           !player.currentItem.isNil
        {
            DispatchQueue.main.async {
                player.avPlayerBackend.switchToMPVOnPipClose = false
                player.saveTime {
                    player.changeActiveBackend(from: .appleAVPlayer, to: .mpv)
                }
            }
        }

        player.playingInPictureInPicture = false
    }

    func pictureInPictureControllerWillStopPictureInPicture(_: AVPictureInPictureController) {}

    func pictureInPictureController(
        _: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        var delay = 0.0
        #if os(iOS)
            if player.currentItem.isNil {
                delay = 0.5
            }
        #endif

        if !player.currentItem.isNil {
            player?.show()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            completionHandler(true)
        }
    }
}
