import AVKit
import SwiftUI

final class PlayerViewController: NSViewController {
    var playerModel: PlayerModel!
    var playerView = AVPlayerView()
    var pictureInPictureDelegate = PictureInPictureDelegate()

    override func viewDidDisappear() {
        if !playerModel.playingInPictureInPicture {
            playerModel.pause()
        }
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
