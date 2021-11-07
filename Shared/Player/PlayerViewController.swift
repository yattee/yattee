import AVKit
import Logging
import SwiftUI

final class PlayerViewController: UIViewController {
    var playerLoaded = false
    var navigationModel: NavigationModel!
    var playerModel: PlayerModel!
    var playerViewController = AVPlayerViewController()

    var aspectRatio: Double? {
        let ratio = Double(playerViewController.videoBounds.width) / Double(playerViewController.videoBounds.height)

        if !ratio.isFinite {
            return VideoPlayerView.defaultAspectRatio
        }

        return [ratio, 1.0].max()!
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        loadPlayer()

        #if os(tvOS)
            if !playerViewController.isBeingPresented, !playerViewController.isBeingDismissed {
                present(playerViewController, animated: false)
            }
        #endif
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
            playerViewController.customInfoViewControllers = [
                infoViewController([.related], title: "Related"),
                infoViewController([.playingNext, .playedPreviously], title: "Playing Next")
            ]
        #else
            embedViewController()
        #endif
    }

    #if os(tvOS)
        func infoViewController(
            _ sections: [NowPlayingView.ViewSection],
            title: String
        ) -> UIHostingController<AnyView> {
            let controller = UIHostingController(rootView:
                AnyView(
                    NowPlayingView(sections: sections, inInfoViewController: true)
                        .frame(maxHeight: 600)
                        .environmentObject(playerModel)
                )
            )

            controller.title = title

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
        true
    }

    func playerViewControllerWillBeginDismissalTransition(_: AVPlayerViewController) {}

    func playerViewControllerDidEndDismissalTransition(_: AVPlayerViewController) {
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

    func playerViewController(
        _ playerViewController: AVPlayerViewController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if self.navigationModel.presentingChannel {
                self.playerModel.playerNavigationLinkActive = true
            } else {
                self.playerModel.presentPlayer()
            }

            #if os(tvOS)
                if self.playerModel.playingInPictureInPicture {
                    self.present(playerViewController, animated: false) {
                        completionHandler(true)
                    }
                }
            #else
                completionHandler(true)
            #endif
        }
    }

    func playerViewControllerWillStartPictureInPicture(_: AVPlayerViewController) {
        playerModel.playingInPictureInPicture = true
        playerModel.playerNavigationLinkActive = false
    }

    func playerViewControllerWillStopPictureInPicture(_: AVPlayerViewController) {
        playerModel.playingInPictureInPicture = false
    }
}
