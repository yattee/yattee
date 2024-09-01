import AVKit
import Defaults
import SwiftUI

#if !os(macOS)
    final class AppleAVPlayerViewControllerDelegate: NSObject, AVPlayerViewControllerDelegate {
        #if os(iOS)
            @Default(.rotateToLandscapeOnEnterFullScreen) private var rotateToLandscapeOnEnterFullScreen
            @Default(.avPlayerUsesSystemControls) private var avPlayerUsesSystemControls
        #endif

        var player: PlayerModel { .shared }

        func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_: AVPlayerViewController) -> Bool {
            false
        }

        #if os(iOS)
            func playerViewController(_: AVPlayerViewController, willBeginFullScreenPresentationWithAnimationCoordinator _: UIViewControllerTransitionCoordinator) {
                if PlayerModel.shared.currentVideoIsLandscape {
                    let delay = PlayerModel.shared.activeBackend == .appleAVPlayer && avPlayerUsesSystemControls ? 0.8 : 0
                    // not sure why but first rotation call is ignore so doing rotate to same orientation first
                    Delay.by(delay) {
                        let orientation = OrientationTracker.shared.currentDeviceOrientation.isLandscape ? OrientationTracker.shared.currentInterfaceOrientation : self.rotateToLandscapeOnEnterFullScreen.interaceOrientation
                        Orientation.lockOrientation(.allButUpsideDown, andRotateTo: OrientationTracker.shared.currentInterfaceOrientation)
                        Orientation.lockOrientation(.allButUpsideDown, andRotateTo: orientation)
                    }
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
                            if Constants.isIPhone {
                                Orientation.lockOrientation(.allButUpsideDown, andRotateTo: .portrait)
                            }

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
