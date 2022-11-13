import Defaults
import Foundation
import SwiftUI

extension VideoPlayerView {
    func configureOrientationUpdatesBasedOnAccelerometer() {
        let currentOrientation = OrientationTracker.shared.currentInterfaceOrientation
        if currentOrientation.isLandscape,
           Defaults[.enterFullscreenInLandscape],
           !Defaults[.honorSystemOrientationLock],
           !player.playingFullScreen,
           !player.currentItem.isNil,
           player.lockedOrientation.isNil || player.lockedOrientation!.contains(.landscape),
           !player.playingInPictureInPicture,
           player.presentingPlayer
        {
            DispatchQueue.main.async {
                player.controls.presentingControls = false
                player.enterFullScreen(showControls: false)
            }

            player.onPresentPlayer.append {
                Orientation.lockOrientation(.allButUpsideDown, andRotateTo: currentOrientation)
            }
        }

        orientationObserver = NotificationCenter.default.addObserver(
            forName: OrientationTracker.deviceOrientationChangedNotification,
            object: nil,
            queue: .main
        ) { _ in
            guard !Defaults[.honorSystemOrientationLock],
                  player.presentingPlayer,
                  !player.playingInPictureInPicture,
                  player.lockedOrientation.isNil
            else {
                return
            }

            let orientation = OrientationTracker.shared.currentInterfaceOrientation

            guard lastOrientation != orientation else {
                return
            }

            lastOrientation = orientation

            DispatchQueue.main.async {
                guard Defaults[.enterFullscreenInLandscape],
                      player.presentingPlayer
                else {
                    return
                }

                orientationDebouncer.callback = {
                    DispatchQueue.main.async {
                        if orientation.isLandscape {
                            player.controls.presentingControls = false
                            player.enterFullScreen(showControls: false)
                            Orientation.lockOrientation(OrientationTracker.shared.currentInterfaceOrientationMask, andRotateTo: orientation)
                        } else {
                            player.exitFullScreen(showControls: false)
                            Orientation.lockOrientation(.allButUpsideDown, andRotateTo: .portrait)
                        }
                    }
                }

                orientationDebouncer.call()
            }
        }
    }

    func stopOrientationUpdates() {
        guard let observer = orientationObserver else { return }
        NotificationCenter.default.removeObserver(observer)
    }
}
