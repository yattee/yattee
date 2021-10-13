import AVKit
import Logging
import SwiftUI

final class PlayerViewController: UIViewController {
    var api: InvidiousAPI!
    var playerLoaded = false
    var playerModel: PlayerModel!
    var playerViewController = AVPlayerViewController()
    var resolution: Stream.ResolutionSetting!
    var shouldResume = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        loadPlayer()

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func loadPlayer() {
        guard !playerLoaded else {
            return
        }

        playerModel.controller = self
        playerViewController.player = playerModel.player
        playerViewController.allowsPictureInPicturePlayback = true
        playerViewController.delegate = self

        #if os(tvOS)
            playerModel.avPlayerViewController = playerViewController
            playerViewController.customInfoViewControllers = [playerQueueInfoViewController]
            present(playerViewController, animated: false)
        #else
            embedViewController()
        #endif

        playerLoaded = true
    }

    #if os(tvOS)
        var playerQueueInfoViewController: UIHostingController<AnyView> {
            let controller = UIHostingController(rootView:
                AnyView(
                    NowPlayingView(infoViewController: true)
                        .frame(maxHeight: 600)
                        .environmentObject(playerModel)
                )
            )

            controller.title = "Playing Next"

            return controller
        }
    #else
        func embedViewController() {
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

    func playerViewControllerWillBeginDismissalTransition(_: AVPlayerViewController) {
        shouldResume = playerModel.isPlaying
    }

    func playerViewControllerDidEndDismissalTransition(_: AVPlayerViewController) {
        if shouldResume {
            playerModel.player.play()
        }

        dismiss(animated: false)
    }

    func playerViewController(
        _: AVPlayerViewController,
        willBeginFullScreenPresentationWithAnimationCoordinator _: UIViewControllerTransitionCoordinator
    ) {}

    func playerViewController(
        _: AVPlayerViewController,
        willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
    ) {
        coordinator.animate(alongsideTransition: nil) { context in
            if !context.isCancelled {
                #if os(iOS)
                    if self.traitCollection.verticalSizeClass == .compact {
                        self.dismiss(animated: true)
                    }
                #endif
            }
        }
    }

    func playerViewControllerWillStartPictureInPicture(_: AVPlayerViewController) {}

    func playerViewControllerWillStopPictureInPicture(_: AVPlayerViewController) {}
}
