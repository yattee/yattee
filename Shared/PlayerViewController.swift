import AVKit
import Logging
import SwiftUI

final class PlayerViewController: UIViewController {
    var video: Video!

    var playerLoaded = false
    var player = AVPlayer()
    var playerState: PlayerState! = PlayerState()
    var playerViewController = AVPlayerViewController()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        loadPlayer()

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        #if os(iOS)
            if !playerState.playingOutsideViewController {
                playerViewController.player?.replaceCurrentItem(with: nil)
                playerViewController.player = nil

                try? AVAudioSession.sharedInstance().setActive(false)
            }
        #endif

        super.viewDidDisappear(animated)
    }

    func loadPlayer() {
        guard !playerLoaded else {
            return
        }

        playerState.player = player
        playerViewController.player = playerState.player
        playerState.loadVideo(video)

        #if os(tvOS)
            present(playerViewController, animated: false)
        #else
            embedViewController()
        #endif

        playerViewController.allowsPictureInPicturePlayback = true
        playerViewController.delegate = self
        playerLoaded = true
    }

    #if !os(tvOS)
        func embedViewController() {
            playerViewController.exitsFullScreenWhenPlaybackEnds = true
            playerViewController.view.frame = view.bounds

            addChild(playerViewController)
            view.addSubview(playerViewController.view)

            playerViewController.didMove(toParent: self)
        }
    #endif
}

extension PlayerViewController: AVPlayerViewControllerDelegate {
    func playerViewControllerShouldDismiss(_: AVPlayerViewController) -> Bool {
        true
    }

    func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_: AVPlayerViewController) -> Bool {
        false
    }

    func playerViewControllerDidEndDismissalTransition(_: AVPlayerViewController) {
        playerState.playingOutsideViewController = false
        dismiss(animated: false)
    }

    func playerViewController(
        _: AVPlayerViewController,
        willBeginFullScreenPresentationWithAnimationCoordinator _: UIViewControllerTransitionCoordinator
    ) {
        playerState.playingOutsideViewController = true
    }

    func playerViewController(
        _: AVPlayerViewController,
        willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
    ) {
        coordinator.animate(alongsideTransition: nil) { context in
            if !context.isCancelled {
                self.playerState.playingOutsideViewController = false
            }
        }
    }

    func playerViewControllerWillStartPictureInPicture(_: AVPlayerViewController) {
        playerState.playingOutsideViewController = true
    }

    func playerViewControllerWillStopPictureInPicture(_: AVPlayerViewController) {
        playerState.playingOutsideViewController = false
    }
}
