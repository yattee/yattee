import AVKit
import SwiftUI

final class PlayerViewController: NSViewController {
    var video: Video!

    var api: InvidiousAPI!
    var player = AVPlayer()
    var playerModel: PlayerModel!
    var playback: PlaybackModel!
    var playerView = AVPlayerView()
    var resolution: Stream.ResolutionSetting!

    override func viewDidDisappear() {
        playerView.player?.replaceCurrentItem(with: nil)
        playerView.player = nil

        playerModel.player = nil
        playerModel = nil

        super.viewDidDisappear()
    }

    override func loadView() {
        playerModel = PlayerModel(playback: playback, api: api, resolution: resolution)

        guard playerModel.player.isNil else {
            return
        }

        playerModel.player = player
        playerView.player = playerModel.player

        playerView.allowsPictureInPicturePlayback = true
        playerView.showsFullScreenToggleButton = true

        view = playerView

        DispatchQueue.main.async {
            self.playerModel.loadVideo(self.video)
        }
    }
}
