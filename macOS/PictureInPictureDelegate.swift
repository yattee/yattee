import AVKit
import Foundation

final class PictureInPictureDelegate: NSObject, AVPlayerViewPictureInPictureDelegate {
    var playerModel: PlayerModel!

    func playerViewShouldAutomaticallyDismissAtPicture(inPictureStart _: AVPlayerView) -> Bool {
        false
    }

    func playerViewWillStartPicture(inPicture _: AVPlayerView) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.playerModel.playingInPictureInPicture = true
            self?.playerModel.hide()
        }
    }

    func playerViewWillStopPicture(inPicture _: AVPlayerView) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.playerModel.playingInPictureInPicture = false
            self?.playerModel.show()
        }
    }

    func playerView(
        _: AVPlayerView,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: (Bool) -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.playerModel.show()
        }
        completionHandler(true)
    }
}
