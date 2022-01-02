import AVKit
import Defaults
import SwiftUI

final class PlayerViewController: UIViewController {
    var playerLoaded = false
    var commentsModel: CommentsModel!
    var navigationModel: NavigationModel!
    var playerModel: PlayerModel!
    var subscriptionsModel: SubscriptionsModel!
    var playerView = AVPlayerViewController()

    #if !os(tvOS)
        var aspectRatio: Double? {
            let ratio = Double(playerView.videoBounds.width) / Double(playerView.videoBounds.height)

            guard ratio.isFinite else {
                return VideoPlayerView.defaultAspectRatio // swiftlint:disable:this implicit_return
            }

            return [ratio, 1.0].max()!
        }
    #endif

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        loadPlayer()

        #if os(tvOS)
            if !playerView.isBeingPresented, !playerView.isBeingDismissed {
                present(playerView, animated: false)
            }
        #endif
    }

    #if os(tvOS)
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)

            if !playerModel.presentingPlayer, !Defaults[.pauseOnHidingPlayer], !playerModel.isPlaying {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.playerModel.play()
                }
            }
        }
    #endif

    func loadPlayer() {
        guard !playerLoaded else {
            return
        }

        playerModel.controller = self
        playerView.player = playerModel.player
        playerView.allowsPictureInPicturePlayback = true
        #if os(iOS)
            if #available(iOS 14.2, *) {
                playerView.canStartPictureInPictureAutomaticallyFromInline = true
            }
        #endif
        playerView.delegate = self

        #if os(tvOS)
            var infoViewControllers = [UIHostingController<AnyView>]()
            if CommentsModel.enabled {
                infoViewControllers.append(infoViewController([.comments], title: "Comments"))
            }

            var queueSections = [NowPlayingView.ViewSection.playingNext]
            if Defaults[.showHistoryInPlayer] {
                queueSections.append(.playedPreviously)
            }

            infoViewControllers.append(contentsOf: [
                infoViewController([.related], title: "Related"),
                infoViewController(queueSections, title: "Queue")
            ])

            playerView.customInfoViewControllers = infoViewControllers
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
                        .environmentObject(commentsModel)
                        .environmentObject(playerModel)
                        .environmentObject(subscriptionsModel)
                )
            )

            controller.title = title

            return controller
        }
    #else
        func embedViewController() {
            playerView.view.frame = view.bounds

            addChild(playerView)
            view.addSubview(playerView.view)

            playerView.didMove(toParent: self)
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
        _: AVPlayerViewController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if self.navigationModel.presentingChannel {
                self.playerModel.playerNavigationLinkActive = true
            } else {
                self.playerModel.show()
            }

            #if os(tvOS)
                if self.playerModel.playingInPictureInPicture {
                    self.present(self.playerView, animated: false) {
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
