import AVKit
import Foundation

final class PictureInPictureDelegate: NSObject, AVPlayerViewPictureInPictureDelegate {
    var playerModel: PlayerModel!

    func playerViewShouldAutomaticallyDismissAtPicture(inPictureStart _: AVPlayerView) -> Bool {
        false
    }

    func playerViewWillStartPicture(inPicture _: AVPlayerView) {
        playerModel.playingInPictureInPicture = true
        playerModel.presentingPlayer = false
    }

    func playerViewWillStopPicture(inPicture _: AVPlayerView) {
        playerModel.playingInPictureInPicture = false
        playerModel.presentPlayer()
    }

    func playerView(
        _: AVPlayerView,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: (Bool) -> Void
    ) {
        playerModel.presentingPlayer = true
        completionHandler(true)
    }
}
