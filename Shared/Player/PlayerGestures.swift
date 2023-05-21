import Defaults
import SwiftUI

struct PlayerGestures: View {
    private var player = PlayerModel.shared
    @ObservedObject private var model = PlayerControlsModel.shared

    @Default(.avPlayerUsesSystemControls) private var avPlayerUsesSystemControls

    var showGestures: Bool {
        player.activeBackend == .mpv || !avPlayerUsesSystemControls
    }

    var body: some View {
        HStack(spacing: 0) {
            if showGestures {
                gestureRectangle
                    .tapRecognizer(
                        tapSensitivity: 0.2,
                        doubleTapAction: {
                            model.presentingControls = false
                            let interval = TimeInterval(Defaults[.gestureBackwardSeekDuration]) ?? 10
                            player.backend.seek(relative: .secondsInDefaultTimescale(-interval), seekType: .userInteracted)
                        },
                        anyTapAction: {
                            singleTapAction()
                            model.update()
                        }
                    )

                gestureRectangle
                    .tapRecognizer(
                        tapSensitivity: 0.2,
                        doubleTapAction: {
                            model.presentingControls = false
                            player.backend.togglePlay()
                        },
                        anyTapAction: singleTapAction
                    )

                gestureRectangle
                    .tapRecognizer(
                        tapSensitivity: 0.2,
                        doubleTapAction: {
                            model.presentingControls = false
                            let interval = TimeInterval(Defaults[.gestureForwardSeekDuration]) ?? 10
                            player.backend.seek(relative: .secondsInDefaultTimescale(interval), seekType: .userInteracted)
                        },
                        anyTapAction: singleTapAction
                    )
            }
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
