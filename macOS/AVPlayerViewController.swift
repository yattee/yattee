import AVKit
import SwiftUI

final class AVPlayerViewController: NSViewController {
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

    override func viewDidDisappear() {
        super.viewDidDisappear()
    }

    override func loadView() {
        playerView.player = playerModel.avPlayer
        pictureInPictureDelegate.playerModel = playerModel

        playerView.allowsPictureInPicturePlayback = true
        playerView.showsFullScreenToggleButton = true

        playerView.pictureInPictureDelegate = pictureInPictureDelegate

        view = playerView
    }
}
