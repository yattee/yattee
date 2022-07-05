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
                        if model.presentingControlsOverlay {
                            model.presentingControls = true
                            model.resetTimer()
                            withAnimation {
                                model.presentingControlsOverlay = false
                            }
                        } else {
                            model.toggle()
                        }
                    },
                    doubleTapAction: {
                        player.backend.seek(relative: .secondsInDefaultTimescale(-10))
                    },
                    anyTapAction: {
                        model.update()
                    }
                )

            gestureRectangle
                .tapRecognizer(
                    tapSensitivity: 0.2,
                    singleTapAction: {
                        if model.presentingControlsOverlay {
                            model.presentingControls = true
                            model.resetTimer()
                            withAnimation {
                                model.presentingControlsOverlay = false
                            }
                        } else {
                            model.toggle()
                        }
                    },
                    doubleTapAction: {
                        player.backend.togglePlay()
                    },
                    anyTapAction: {
                        model.update()
                    }
                )

            gestureRectangle
                .tapRecognizer(
                    tapSensitivity: 0.2,
                    singleTapAction: {
                        if model.presentingControlsOverlay {
                            model.presentingControls = true
                            model.resetTimer()
                            withAnimation {
                                model.presentingControlsOverlay = false
                            }
                        } else {
                            model.toggle()
                        }
                    },
                    doubleTapAction: {
                        player.backend.seek(relative: .secondsInDefaultTimescale(10))
                    },
                    anyTapAction: {
                        model.update()
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
