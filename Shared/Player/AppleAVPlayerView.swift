import AVKit
import Defaults
import SwiftUI

#if !os(macOS)
    final class AppleAVPlayerViewControllerDelegate: NSObject, AVPlayerViewControllerDelegate {
        var player: PlayerModel { .shared }

        func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_: AVPlayerViewController) -> Bool {
            false
        }

        #if os(iOS)
            func playerViewController(_: AVPlayerViewController, willBeginFullScreenPresentationWithAnimationCoordinator _: UIViewControllerTransitionCoordinator) {
                let lockOrientation = player.rotateToLandscapeOnEnterFullScreen.interfaceOrientation
                if player.currentVideoIsLandscape {
                    if player.fullscreenInitiatedByButton {
                        Orientation.lockOrientation(player.isOrientationLocked
                            ? (lockOrientation == .landscapeRight ? .landscapeRight : .landscapeLeft)
                            : .landscape)
                    }
                    let orientation = OrientationTracker.shared.currentDeviceOrientation.isLandscape
                        ? OrientationTracker.shared.currentInterfaceOrientation
                        : player.rotateToLandscapeOnEnterFullScreen.interfaceOrientation

                    Orientation.lockOrientation(
                        player.isOrientationLocked
                            ? (lockOrientation == .landscapeRight ? .landscapeRight : .landscapeLeft)
                            : .all,
                        andRotateTo: orientation
                    )
                }
            }

            func playerViewController(_: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
                let wasPlaying = player.isPlaying
                coordinator.animate(alongsideTransition: nil) { context in
                    if wasPlaying {
                        self.player.play()
                    }
                    if !context.isCancelled {
                        #if os(iOS)
                            if self.player.lockPortraitWhenBrowsing {
                                self.player.lockedOrientation = UIInterfaceOrientationMask.portrait
                            }
                            let rotationOrientation = self.player.lockPortraitWhenBrowsing ? UIInterfaceOrientation.portrait : nil
                            Orientation.lockOrientation(self.player.lockPortraitWhenBrowsing ? .portrait : .all, andRotateTo: rotationOrientation)

                            if wasPlaying {
                                self.player.play()
                            }

                            self.player.playingFullScreen = false
                        #endif
                    }
                }
            }

            func playerViewController(_: AVPlayerViewController, restoreUserInterfaceForFullScreenExitWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
                withAnimation(nil) {
                    player.presentingPlayer = true
                }

                completionHandler(true)
            }
        #endif

        func playerViewControllerWillStartPictureInPicture(_: AVPlayerViewController) {}

        func playerViewControllerWillStopPictureInPicture(_: AVPlayerViewController) {}

        func playerViewControllerDidStartPictureInPicture(_: AVPlayerViewController) {
            player.playingInPictureInPicture = true
            player.avPlayerBackend.startPictureInPictureOnPlay = false
            player.avPlayerBackend.startPictureInPictureOnSwitch = false
            player.controls.objectWillChange.send()

            if Defaults[.closePlayerOnOpeningPiP] { Delay.by(0.1) { self.player.hide() } }
        }

        func playerViewControllerDidStopPictureInPicture(_: AVPlayerViewController) {
            player.playingInPictureInPicture = false
            player.controls.objectWillChange.send()
        }

        func playerViewController(_: AVPlayerViewController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
            player.presentingPlayer = true
            withAnimation(.linear(duration: 0.3)) {
                self.player.playingInPictureInPicture = false
                Delay.by(0.5) {
                    completionHandler(true)
                    Delay.by(0.2) {
                        self.player.play()
                    }
                }
            }
        }
    }
#endif

#if os(iOS)
    struct AppleAVPlayerView: UIViewControllerRepresentable {
        @State private var controller = AVPlayerViewController()

        func makeUIViewController(context _: Context) -> AVPlayerViewController {
            setupController()
            return controller
        }

        func updateUIViewController(_: AVPlayerViewController, context _: Context) {
            setupController()
        }

        func setupController() {
            controller.delegate = PlayerModel.shared.appleAVPlayerViewControllerDelegate
            controller.allowsPictureInPicturePlayback = true
            if #available(iOS 14.2, *) {
                controller.canStartPictureInPictureAutomaticallyFromInline = true
            }
            PlayerModel.shared.avPlayerBackend.controller = controller
        }
    }

    struct AppleAVPlayerLayerView: UIViewRepresentable {
        func makeUIView(context _: Context) -> some UIView {
            PlayerLayerView(frame: .zero)
        }

        func updateUIView(_: UIViewType, context _: Context) {}
    }

#elseif os(tvOS)
    struct AppleAVPlayerView: UIViewControllerRepresentable {
        func makeUIViewController(context _: Context) -> AppleAVPlayerViewController {
            let controller = AppleAVPlayerViewController()
            PlayerModel.shared.avPlayerBackend.controller = controller

            return controller
        }

        func updateUIViewController(_: AppleAVPlayerViewController, context _: Context) {
            PlayerModel.shared.rebuildTVMenu()
        }
    }
#else
    struct AppleAVPlayerView: NSViewRepresentable {
        func makeNSView(context _: Context) -> some NSView {
            let view = AVPlayerView()
            view.player = PlayerModel.shared.avPlayerBackend.avPlayer
            view.showsFullScreenToggleButton = true
            view.allowsPictureInPicturePlayback = true
            view.pictureInPictureDelegate = MacOSPiPDelegate.shared
            return view
        }

        func updateNSView(_: NSViewType, context _: Context) {}
    }

    struct AppleAVPlayerLayerView: NSViewRepresentable {
        func makeNSView(context _: Context) -> some NSView {
            PlayerLayerView(frame: .zero)
        }

        func updateNSView(_: NSViewType, context _: Context) {}
    }
#endif
