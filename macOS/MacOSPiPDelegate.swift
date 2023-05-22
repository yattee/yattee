import AVKit
import Foundation

final class MacOSPiPDelegate: NSObject, AVPlayerViewPictureInPictureDelegate {
    static let shared = MacOSPiPDelegate()

    var playerModel: PlayerModel { .shared }

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
        playerModel.show()
        playerModel.playingInPictureInPicture = false
    }

    func playerView(
        _: AVPlayerView,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: (Bool) -> Void
    ) {
        completionHandler(true)
    }
}
