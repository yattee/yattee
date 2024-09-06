import Defaults
import Foundation
import Logging
import Repeat
import SwiftUI

final class OrientationModel {
    static var shared = OrientationModel()
    let logger = Logger(label: "stream.yattee.orientation.model")

    var orientation = UIInterfaceOrientation.portrait
    var lastOrientation: UIInterfaceOrientation?
    var orientationDebouncer = Debouncer(.milliseconds(300))
    var orientationObserver: Any?

    @Default(.lockPortraitWhenBrowsing) private var lockPortraitWhenBrowsing
    @Default(.enterFullscreenInLandscape) private var enterFullscreenInLandscape

    private var player = PlayerModel.shared

    func startOrientationUpdates() {
        // Ensure the orientation observer is active
        orientationObserver = NotificationCenter.default.addObserver(
            forName: OrientationTracker.deviceOrientationChangedNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.logger.info("Notification received: Device orientation changed.")

            // We only allow .portrait and are not showing the player
            guard (!self.player.presentingPlayer && !self.lockPortraitWhenBrowsing) || self.player.presentingPlayer
            else {
                return
            }

            let orientation = OrientationTracker.shared.currentInterfaceOrientation
            self.logger.info("Current interface orientation: \(orientation)")

            // Always update lastOrientation to keep track of the latest state
            if self.lastOrientation != orientation {
                self.lastOrientation = orientation
                self.logger.info("Orientation changed to: \(orientation)")
            } else {
                self.logger.info("Orientation has not changed.")
            }

            // Only take action if the player is active and presenting
            guard (!self.player.isOrientationLocked && !self.player.playingInPictureInPicture) || (!self.lockPortraitWhenBrowsing && !self.player.presentingPlayer) || (!self.lockPortraitWhenBrowsing && self.player.presentingPlayer && !self.player.isOrientationLocked)
            else {
                self.logger.info("Only updating orientation without actions.")
                return
            }

            DispatchQueue.main.async {
                self.orientationDebouncer.callback = {
                    DispatchQueue.main.async {
                        if orientation.isLandscape {
                            if self.enterFullscreenInLandscape, self.player.presentingPlayer {
                                self.logger.info("Entering fullscreen because orientation is landscape.")
                                self.player.controls.presentingControls = false
                                self.player.enterFullScreen(showControls: false)
                            }
                            Orientation.lockOrientation(OrientationTracker.shared.currentInterfaceOrientationMask, andRotateTo: orientation)
                        } else {
                            self.logger.info("Exiting fullscreen because orientation is portrait.")
                            if self.player.playingFullScreen {
                                self.player.exitFullScreen(showControls: false)
                            }
                            if self.lockPortraitWhenBrowsing {
                                Orientation.lockOrientation(.portrait, andRotateTo: .portrait)
                            } else {
                                Orientation.lockOrientation(OrientationTracker.shared.currentInterfaceOrientationMask, andRotateTo: orientation)
                            }
                        }
                    }
                }
                self.orientationDebouncer.call()
            }
        }
    }

    func lockOrientation(_ orientation: UIInterfaceOrientationMask, andRotateTo rotateOrientation: UIInterfaceOrientation? = nil) {
        logger.info("Locking orientation to: \(orientation), rotating to: \(String(describing: rotateOrientation)).")
        if let rotateOrientation {
            self.orientation = rotateOrientation
            lastOrientation = rotateOrientation
        }
        Orientation.lockOrientation(orientation, andRotateTo: rotateOrientation)
    }
}
