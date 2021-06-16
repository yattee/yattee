import AVKit

class StreamAVPlayerViewController: AVPlayerViewController {
    var state: PlayerState?

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        state?.destroyPlayer()
    }
}
