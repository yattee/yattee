import AVKit
import Defaults
import Foundation
import SwiftUI

final class PiPDelegate: NSObject, AVPictureInPictureControllerDelegate {
    var player: PlayerModel { .shared }

    func pictureInPictureController(
        _: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        print(error.localizedDescription)
    }

    func pictureInPictureControllerWillStartPictureInPicture(_: AVPictureInPictureController) {}

    func pictureInPictureControllerDidStartPictureInPicture(_: AVPictureInPictureController) {
        player.play()

        player.playingInPictureInPicture = true
        player.avPlayerBackend.startPictureInPictureOnPlay = false
        player.avPlayerBackend.startPictureInPictureOnSwitch = false
        player.controls.objectWillChange.send()

        if Defaults[.closePlayerOnOpeningPiP] { Delay.by(0.1) { self.player.hide() } }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_: AVPictureInPictureController) {
        player.playingInPictureInPicture = false
        player.controls.objectWillChange.send()
    }

    func pictureInPictureControllerWillStopPictureInPicture(_: AVPictureInPictureController) {
        player.show()
    }

    func pictureInPictureController(
        _: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        let wasPlaying = player.isPlaying

        var delay = 0.0
        #if os(iOS)
            if !player.presentingPlayer {
                delay = 0.5
            }
            if player.currentItem.isNil {
                delay = 1
            }
        #endif

        if !player.currentItem.isNil, !player.musicMode {
            player.show()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            withAnimation(.linear(duration: 0.3)) {
                self?.player.playingInPictureInPicture = false
            }

            if wasPlaying {
                Delay.by(1) {
                    self?.player.play()
                }
            }
            completionHandler(true)
        }
    }
}
