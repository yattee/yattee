import SwiftUI

struct PlayerGestures: View {
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<PlayerControlsModel> private var model

    var body: some View {
        HStack(spacing: 0) {
            gestureRectangle
                .tapRecognizer(
                    tapSensitivity: 0.2,
                    singleTapAction: {
                        model.toggle()
                    },
                    doubleTapAction: {
                        player.backend.seek(relative: .secondsInDefaultTimescale(-10))
                    }
                )

            gestureRectangle
                .tapRecognizer(
                    tapSensitivity: 0.2,
                    singleTapAction: {
                        model.toggle()
                    },
                    doubleTapAction: {
                        player.backend.togglePlay()
                    }
                )

            gestureRectangle
                .tapRecognizer(
                    tapSensitivity: 0.2,
                    singleTapAction: {
                        model.toggle()
                    },
                    doubleTapAction: {
                        player.backend.seek(relative: .secondsInDefaultTimescale(10))
                    }
                )
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
