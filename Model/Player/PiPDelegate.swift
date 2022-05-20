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

    func pictureInPictureControllerDidStartPictureInPicture(_: AVPictureInPictureController) {}

    func pictureInPictureControllerDidStopPictureInPicture(_: AVPictureInPictureController) {
        if player?.avPlayerBackend.switchToMPVOnPipClose ?? false {
            DispatchQueue.main.async { [weak player] in
                player?.avPlayerBackend.switchToMPVOnPipClose = false
                player?.saveTime { [weak player] in
                    player?.changeActiveBackend(from: .appleAVPlayer, to: .mpv)
                }
            }
        }
    }

    func pictureInPictureControllerWillStopPictureInPicture(_: AVPictureInPictureController) {}

    func pictureInPictureController(
        _: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler _: @escaping (Bool) -> Void
    ) {}
}
