import AVKit
import Logging
import SwiftUI

final class PlayerViewController: UIViewController {
    var video: Video!

    var api: InvidiousAPI!
    var playerLoaded = false
    var player = AVPlayer()
    var playerModel: PlayerModel!
    var playback: PlaybackModel!
    var playerViewController = AVPlayerViewController()
    var resolution: Stream.ResolutionSetting!

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        loadPlayer()

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        #if os(iOS)
            if !playerModel.playingOutsideViewController {
                playerViewController.player?.replaceCurrentItem(with: nil)
                playerViewController.player = nil

                try? AVAudioSession.sharedInstance().setActive(false)
            }
        #endif

        super.viewDidDisappear(animated)
    }

    func loadPlayer() {
        playerModel = PlayerModel(playback: playback, api: api, resolution: resolution)

        guard !playerLoaded else {
            return
        }

        playerModel.player = player
        playerViewController.player = playerModel.player
        playerModel.loadVideo(video)

        #if os(tvOS)
            present(playerViewController, animated: false)

            addItemDidPlayToEndTimeObserver()
        #else
            embedViewController()
        #endif

        playerViewController.allowsPictureInPicturePlayback = true
        playerViewController.delegate = self
        playerLoaded = true
    }

    #if os(tvOS)
        func addItemDidPlayToEndTimeObserver() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(itemDidPlayToEndTime),
                name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                object: nil
            )
        }

        @objc func itemDidPlayToEndTime() {
            playerViewController.dismiss(animated: true) {
                self.dismiss(animated: false)
            }
        }
    #else
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
        playerModel.playingOutsideViewController = false
        dismiss(animated: false)
    }

    func playerViewController(
        _: AVPlayerViewController,
        willBeginFullScreenPresentationWithAnimationCoordinator _: UIViewControllerTransitionCoordinator
    ) {
        playerModel.playingOutsideViewController = true
    }

    func playerViewController(
        _: AVPlayerViewController,
        willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
    ) {
        coordinator.animate(alongsideTransition: nil) { context in
            if !context.isCancelled {
                self.playerModel.playingOutsideViewController = false

                #if os(iOS)
                    if self.traitCollection.verticalSizeClass == .compact {
                        self.dismiss(animated: true)
                    }
                #endif
            }
        }
    }

    func playerViewControllerWillStartPictureInPicture(_: AVPlayerViewController) {
        playerModel.playingOutsideViewController = true
    }

    func playerViewControllerWillStopPictureInPicture(_: AVPlayerViewController) {
        playerModel.playingOutsideViewController = false
    }
}
