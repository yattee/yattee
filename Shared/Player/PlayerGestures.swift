import Defaults
import SwiftUI

struct PlayerGestures: View {
    private var player = PlayerModel.shared
    @ObservedObject private var model = PlayerControlsModel.shared

    @Default(.gestureBackwardSeekDuration) private var gestureBackwardSeekDuration
    @Default(.gestureForwardSeekDuration) private var gestureForwardSeekDuration

    var body: some View {
        HStack(spacing: 0) {
            gestureRectangle
                .tapRecognizer(
                    tapSensitivity: 0.2,
                    singleTapAction: { singleTapAction() },
                    doubleTapAction: {
                        let interval = TimeInterval(gestureBackwardSeekDuration) ?? 10
                        player.backend.seek(relative: .secondsInDefaultTimescale(-interval), seekType: .userInteracted)
                    },
                    anyTapAction: {
                        model.update()
                    }
                )

            gestureRectangle
                .tapRecognizer(
                    tapSensitivity: 0.2,
                    singleTapAction: { singleTapAction() },
                    doubleTapAction: {
                        player.backend.togglePlay()
                    }
                )

            gestureRectangle
                .tapRecognizer(
                    tapSensitivity: 0.2,
                    singleTapAction: { singleTapAction() },
                    doubleTapAction: {
                        let interval = TimeInterval(gestureForwardSeekDuration) ?? 10
                        player.backend.seek(relative: .secondsInDefaultTimescale(interval), seekType: .userInteracted)
                    }
                )
        }
    }

    func singleTapAction() {
        if model.presentingOverlays {
            withAnimation(PlayerControls.animation) {
                model.hideOverlays()
            }
        } else {
            model.toggle()
        }
    }

    var gestureRectangle: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlayerGestures_Previews: PreviewProvider {
    static var previews: some View {
        PlayerGestures()
    }
}
