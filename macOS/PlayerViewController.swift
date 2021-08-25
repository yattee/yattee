import AVKit
import SwiftUI

final class PlayerViewController: NSViewController {
    var video: Video!

    var player = AVPlayer()
    var playerState: PlayerState!
    var playbackState: PlaybackState!
    var playerView = AVPlayerView()

    override func viewDidDisappear() {
        playerView.player?.replaceCurrentItem(with: nil)
        playerView.player = nil

        playerState.player = nil
        playerState = nil

        super.viewDidDisappear()
    }

    override func loadView() {
        playerState = PlayerState(playbackState: playbackState)

        guard playerState.player == nil else {
            return
        }

        playerState.player = player
        playerView.player = playerState.player

        playerView.allowsPictureInPicturePlayback = true
        playerView.showsFullScreenToggleButton = true

        view = playerView

        playerState.loadVideo(video)
    }
}
