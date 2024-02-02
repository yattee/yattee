import AVKit
import SwiftUI

final class PlayerViewController: NSViewController {
    var playerModel: PlayerModel!
    var playerView = AVPlayerView()
    var pictureInPictureDelegate = PictureInPictureDelegate()

    var aspectRatio: Double? {
        let ratio = Double(playerView.videoBounds.width) / Double(playerView.videoBounds.height)

        if !ratio.isFinite {
            return VideoPlayerView.defaultAspectRatio
        }

        return [ratio, 1.0].max()!
    }

    func viewDidDisappear() {
        super.viewDidDisappear()
    }

    override func loadView() {
        playerView.player = playerModel.player
        pictureInPictureDelegate.playerModel = playerModel

        playerView.allowsPictureInPicturePlayback = true
        playerView.showsFullScreenToggleButton = true

        playerView.pictureInPictureDelegate = pictureInPictureDelegate

        view = playerView
    }
}
