import Defaults
import Foundation
import Repeat
import SwiftUI

final class OrientationModel {
    static var shared = OrientationModel()

    var orientation = UIInterfaceOrientation.portrait
    var lastOrientation: UIInterfaceOrientation?
    var orientationDebouncer = Debouncer(.milliseconds(300))
    var orientationObserver: Any?

    private var player = PlayerModel.shared

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
                self.player.controls.presentingControls = false
                self.player.enterFullScreen(showControls: false)
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
                  self.player.presentingPlayer,
                  !self.player.playingInPictureInPicture,
                  self.player.lockedOrientation.isNil
            else {
                return
            }

            let orientation = OrientationTracker.shared.currentInterfaceOrientation

            guard self.lastOrientation != orientation else {
                return
            }

            self.lastOrientation = orientation

            DispatchQueue.main.async {
                guard Defaults[.enterFullscreenInLandscape],
                      self.player.presentingPlayer
                else {
                    return
                }

                self.orientationDebouncer.callback = {
                    DispatchQueue.main.async {
                        if orientation.isLandscape {
                            self.player.controls.presentingControls = false
                            self.player.enterFullScreen(showControls: false)
                        } else {
                            self.player.exitFullScreen(showControls: false)
                        }
                    }
                }

                self.orientationDebouncer.call()
            }
        }
    }

    func stopOrientationUpdates() {
        guard let observer = orientationObserver else { return }
        NotificationCenter.default.removeObserver(observer)
    }

    func lockOrientation(_ orientation: UIInterfaceOrientationMask, andRotateTo rotateOrientation: UIInterfaceOrientation? = nil) {
        if let rotateOrientation {
            self.orientation = rotateOrientation
            lastOrientation = rotateOrientation
        }
        Orientation.lockOrientation(orientation, andRotateTo: rotateOrientation)
    }
}
