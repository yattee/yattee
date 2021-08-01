import AVKit
import Logging
import SwiftUI

final class PlayerViewController: UIViewController {
    var video: Video!

    var playerLoaded = false
    var playingFullScreen = false

    var player = AVPlayer()
    var playerState: PlayerState! = PlayerState()
    var playerViewController = AVPlayerViewController()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if !playerLoaded {
            loadPlayer()
        }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        #if os(iOS)
            if !playingFullScreen {
                playerViewController.player?.replaceCurrentItem(with: nil)
                playerViewController.player = nil
            }
        #endif

        super.viewDidDisappear(animated)
    }

    func loadPlayer() {
        playerState.player = player
        playerViewController.player = playerState.player
        playerState.loadVideo(video)

        #if os(tvOS)
            present(playerViewController, animated: false)
        #else
            playerViewController.exitsFullScreenWhenPlaybackEnds = true
            playerViewController.view.frame = view.bounds

            addChild(playerViewController)
            view.addSubview(playerViewController.view)

            playerViewController.didMove(toParent: self)
        #endif

        playerViewController.delegate = self
        playerLoaded = true
    }
}

extension PlayerViewController: AVPlayerViewControllerDelegate {
    func playerViewControllerShouldDismiss(_: AVPlayerViewController) -> Bool {
        true
    }

    func playerViewControllerDidEndDismissalTransition(_: AVPlayerViewController) {
        playingFullScreen = false
        dismiss(animated: false)
    }

    func playerViewController(
        _: AVPlayerViewController,
        willBeginFullScreenPresentationWithAnimationCoordinator _: UIViewControllerTransitionCoordinator
    ) {
        playingFullScreen = true
    }

    func playerViewController(
        _: AVPlayerViewController,
        willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
    ) {
        coordinator.animate(alongsideTransition: nil) { context in
            if !context.isCancelled {
                self.playingFullScreen = false
            }
        }
    }
}
