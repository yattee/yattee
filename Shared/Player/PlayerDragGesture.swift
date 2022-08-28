import Defaults
import SwiftUI

extension VideoPlayerView {
    var playerDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
        #if os(iOS)
            .updating($dragGestureOffset) { value, state, _ in
                guard isVerticalDrag else { return }
                var translation = value.translation
                translation.height = max(0, translation.height)
                state = translation
            }
        #endif
            .updating($dragGestureState) { _, state, _ in
                state = true
            }
            .onChanged { value in
                guard player.presentingPlayer,
                      !playerControls.presentingControlsOverlay else { return }

                if playerControls.presentingControls, !player.musicMode {
                    playerControls.presentingControls = false
                }

                if player.musicMode {
                    player.backend.stopControlsUpdates()
                }

                let verticalDrag = value.translation.height
                let horizontalDrag = value.translation.width

                #if os(iOS)
                    if viewDragOffset > 0, !isVerticalDrag {
                        isVerticalDrag = true
                    }
                #endif

                if !isVerticalDrag, abs(horizontalDrag) > 15, !isHorizontalDrag {
                    isHorizontalDrag = true
                    player.playerTime.resetSeek()
                    viewDragOffset = 0
                }

                if horizontalPlayerGestureEnabled, isHorizontalDrag {
                    player.playerTime.onSeekGestureStart {
                        let timeSeek = (player.playerTime.duration.seconds / player.playerSize.width) * horizontalDrag * seekGestureSpeed
                        player.playerTime.gestureSeek = timeSeek
                    }
                    return
                }

                guard verticalDrag > 0 else { return }
                viewDragOffset = verticalDrag

                if verticalDrag > 60,
                   player.playingFullScreen
                {
                    player.exitFullScreen(showControls: false)
                    #if os(iOS)
                        if Defaults[.rotateToPortraitOnExitFullScreen] {
                            Orientation.lockOrientation(.allButUpsideDown, andRotateTo: .portrait)
                        }
                    #endif
                }
            }
            .onEnded { _ in
                onPlayerDragGestureEnded()
            }
    }

    private func onPlayerDragGestureEnded() {
        if horizontalPlayerGestureEnabled, isHorizontalDrag {
            isHorizontalDrag = false
            player.playerTime.onSeekGestureEnd()
        }

        isVerticalDrag = false

        guard player.presentingPlayer,
              !playerControls.presentingControlsOverlay else { return }

        if viewDragOffset > 100 {
            withAnimation(Constants.overlayAnimation) {
                viewDragOffset = Self.hiddenOffset
            }
        } else {
            withAnimation(Constants.overlayAnimation) {
                viewDragOffset = 0
            }
            player.backend.setNeedsDrawing(true)
            player.show()

            if player.musicMode {
                player.backend.startControlsUpdates()
            }
        }
    }
}
