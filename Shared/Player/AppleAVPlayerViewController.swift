import AVKit
import Defaults
import SwiftUI

final class AppleAVPlayerViewController: UIViewController {
    var playerLoaded = false
    var accountsModel: AccountsModel!
    var commentsModel: CommentsModel!
    var navigationModel: NavigationModel!
    var playerModel: PlayerModel!
    var playlistsModel: PlaylistsModel!
    var subscriptionsModel: SubscriptionsModel!
    var playerView = AVPlayerViewController()

    let persistenceController = PersistenceController.shared

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        loadPlayer()

        if playerModel.presentingPlayer, !playerView.isBeingPresented, !playerView.isBeingDismissed {
            present(playerView, animated: false)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if !playerModel.presentingPlayer, !Defaults[.pauseOnHidingPlayer], !playerModel.isPlaying {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.playerModel.play()
            }
        }
    }

    func loadPlayer() {
        guard !playerLoaded else {
            return
        }

        playerView.player = playerModel.avPlayerBackend.avPlayer
        playerView.allowsPictureInPicturePlayback = true
        playerView.showsPlaybackControls = true
        playerView.delegate = self

        var infoViewControllers = [UIHostingController<AnyView>]()
        infoViewControllers.append(infoViewController([.chapters], title: "Chapters"))
        infoViewControllers.append(infoViewController([.comments], title: "Comments"))

        var queueSections = [NowPlayingView.ViewSection.playingNext]
        if Defaults[.showHistoryInPlayer] {
            queueSections.append(.playedPreviously)
        }

        infoViewControllers.append(contentsOf: [
            infoViewController([.related], title: "Related"),
            infoViewController(queueSections, title: "Queue")
        ])

        playerView.customInfoViewControllers = infoViewControllers
    }

    func infoViewController(
        _ sections: [NowPlayingView.ViewSection],
        title: String
    ) -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView:
            AnyView(
                NowPlayingView(sections: sections, inInfoViewController: true)
                    .frame(maxHeight: 600)
                    .environmentObject(accountsModel)
                    .environmentObject(commentsModel)
                    .environmentObject(playerModel)
                    .environmentObject(playlistsModel)
                    .environmentObject(subscriptionsModel)
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
            )
        )

        controller.title = title

        return controller
    }
}

extension AppleAVPlayerViewController: AVPlayerViewControllerDelegate {
    func playerViewControllerShouldDismiss(_: AVPlayerViewController) -> Bool {
        true
    }

    func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_: AVPlayerViewController) -> Bool {
        true
    }

    func playerViewControllerWillBeginDismissalTransition(_: AVPlayerViewController) {
        if Defaults[.pauseOnHidingPlayer] {
            playerModel.pause()
        }
        dismiss(animated: false)
    }

    func playerViewControllerDidEndDismissalTransition(_: AVPlayerViewController) {}

    func playerViewController(
        _: AVPlayerViewController,
        willBeginFullScreenPresentationWithAnimationCoordinator _: UIViewControllerTransitionCoordinator
    ) {}

    func playerViewController(
        _: AVPlayerViewController,
        willEndFullScreenPresentationWithAnimationCoordinator _: UIViewControllerTransitionCoordinator
    ) {}

    func playerViewController(
        _: AVPlayerViewController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.playerModel.show()
            self.playerModel.setNeedsDrawing(true)

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
    }

    func playerViewControllerWillStopPictureInPicture(_: AVPlayerViewController) {
        playerModel.playingInPictureInPicture = false
    }
}
