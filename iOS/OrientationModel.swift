import Defaults
import Foundation
import Repeat
import SwiftUI

final class OrientationModel {
    static let shared = OrientationModel()

    private var lastOrientation: UIInterfaceOrientation?
    private var orientationDebouncer = Debouncer(.milliseconds(300))
    private var orientationObserver: Any?

    private let player = PlayerModel.shared

    /// Configures orientation updates based on accelerometer data.
    func configureOrientationUpdatesBasedOnAccelerometer() {
        let currentOrientation = OrientationTracker.shared.currentInterfaceOrientation

        if shouldEnterFullScreen(for: currentOrientation) {
            DispatchQueue.main.async {
                self.player.controls.presentingControls = false
                self.player.enterFullScreen(showControls: false)
            }

            player.onPresentPlayer.append {
                self.lockOrientationAndRotate(currentOrientation)
            }
        }

        orientationObserver = NotificationCenter.default.addObserver(
            forName: OrientationTracker.deviceOrientationChangedNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.handleOrientationChange()
        }
    }

    /// Stops orientation updates and removes the observer.
    func stopOrientationUpdates() {
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Locks the orientation and optionally rotates to a specific orientation.
    private func lockOrientationAndRotate(_ rotateOrientation: UIInterfaceOrientation) {
        if Defaults[.lockPortraitWhenBrowsing] {
            // Lock orientation to portrait when browsing
            Orientation.lockOrientation(.portrait)
        } else {
            // Allow all orientations except upside down
            let mask: UIInterfaceOrientationMask = UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
            Orientation.lockOrientation(mask, andRotateTo: rotateOrientation)
        }
    }

    // MARK: - Private Methods

    private func shouldEnterFullScreen(for orientation: UIInterfaceOrientation) -> Bool {
        return orientation.isLandscape &&
            Defaults[.enterFullscreenInLandscape] &&
            !player.playingFullScreen &&
            !player.currentItem.isNil &&
            (player.lockedOrientation.isNil || player.lockedOrientation!.contains(.landscape)) &&
            !player.playingInPictureInPicture &&
            player.presentingPlayer
    }

    private func handleOrientationChange() {
        if Defaults[.lockPortraitWhenBrowsing] {
            Orientation.lockOrientation(.portrait)
            return
        }

        guard player.presentingPlayer, !player.playingInPictureInPicture, player.lockedOrientation.isNil else {
            return
        }

        let orientation = OrientationTracker.shared.currentInterfaceOrientation

        guard lastOrientation != orientation else {
            return
        }

        lastOrientation = orientation

        orientationDebouncer.callback = {
            DispatchQueue.main.async {
                if orientation.isLandscape {
                    self.player.controls.presentingControls = false
                    self.player.enterFullScreen(showControls: false)
                } else {
                    self.player.exitFullScreen(showControls: false)
                }
            }
        }
        orientationDebouncer.call()
    }
}
