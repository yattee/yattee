import Defaults
import SwiftUI

extension VideoPlayerView {
    var playerDragGesture: some Gesture {
        let longPressGesture = LongPressGesture(minimumDuration: 0)
            .updating($isLongPressing) { currentState, gestureState, _ in
                gestureState = currentState
            }
            .onEnded { _ in
                if startTouchTime == nil {
                    startTouchTime = Date()
                }
            }

        let dragGesture = DragGesture(minimumDistance: 30, coordinateSpace: .global)
            .updating($dragGestureOffset) { value, state, _ in
                guard isVerticalDrag else { return }
                var translation = value.translation
                translation.height = max(0, translation.height)
                state = translation
            }
            .updating($dragGestureState) { _, state, _ in
                state = true
            }
            .onChanged { value in
                if abs(value.translation.width) < abs(value.translation.height) {
                    processDragGesture(value)
                } else if getElapsedTouchTime() >= 0.25 {
                    processDragGesture(value)
                }
            }
            .onEnded { value in
                if abs(value.translation.width) < abs(value.translation.height) {
                    onPlayerDragGestureEnded()
                } else if getElapsedTouchTime() >= 0.25 {
                    onPlayerDragGestureEnded()
                }

                startTouchTime = nil
            }
        return longPressGesture.sequenced(before: dragGesture)
    }

    func getElapsedTouchTime() -> TimeInterval {
        guard let startTouchTime = startTouchTime else {
            return 0
        }
        return Date().timeIntervalSince(startTouchTime)
    }

    func processDragGesture(_ value: DragGesture.Value) {
        guard player.presentingPlayer,
              !controlsOverlayModel.presenting,
              dragGestureState else { return }

        if player.controls.presentingControls, !player.musicMode {
            player.controls.presentingControls = false
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

        if !isVerticalDrag,
           horizontalPlayerGestureEnabled,
           abs(horizontalDrag) > seekGestureSensitivity,
           !isHorizontalDrag,
           player.activeBackend == .mpv || !avPlayerUsesSystemControls
        {
            isHorizontalDrag = true
            player.seek.onSeekGestureStart()
            viewDragOffset = 0
        }

        if horizontalPlayerGestureEnabled, isHorizontalDrag {
            player.seek.updateCurrentTime {
                let time = player.backend.playerItemDuration?.seconds ?? 0
                if player.seek.gestureStart.isNil {
                    player.seek.gestureStart = time
                }
                let timeSeek = (time / player.playerSize.width) * horizontalDrag * seekGestureSpeed

                player.seek.gestureSeek = timeSeek
            }
            return
        }

        guard verticalDrag > 0 else { return }
        viewDragOffset = verticalDrag

        if verticalDrag > 60, player.playingFullScreen {
            player.exitFullScreen(showControls: false)
            #if os(iOS)
                if Constants.isIPhone {
                    Orientation.lockOrientation(.allButUpsideDown, andRotateTo: .portrait)
                }
            #endif
        }
    }

    func onPlayerDragGestureEnded() {
        if horizontalPlayerGestureEnabled, isHorizontalDrag {
            isHorizontalDrag = false
            player.seek.onSeekGestureEnd()
        }

        if viewDragOffset > 60,
           player.playingFullScreen
        {
            #if os(iOS)
                player.lockedOrientation = nil
            #endif
            player.exitFullScreen(showControls: false)
            viewDragOffset = 0
            return
        }
        isVerticalDrag = false

        guard player.presentingPlayer,
              !controlsOverlayModel.presenting else { return }

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
