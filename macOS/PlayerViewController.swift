import AVKit
import SwiftUI

final class PlayerViewController: NSViewController {
    var playerModel: PlayerModel!
    var playerView = AVPlayerView()

    override func viewDidDisappear() {
        // TODO: pause on disappear settings
        super.viewDidDisappear()
    }

    override func loadView() {
        playerView.player = playerModel.player

        playerView.allowsPictureInPicturePlayback = true
        playerView.showsFullScreenToggleButton = true

        view = playerView
    }
}
