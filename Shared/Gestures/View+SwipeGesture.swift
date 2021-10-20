import SwiftUI

extension View {
    func onSwipeGesture(
        up: @escaping () -> Void = {},
        down: @escaping () -> Void = {}
    ) -> some View {
        gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { gesture in
                    let translation = gesture.translation

                    if abs(translation.height) > 100_000 {
                        return
                    }

                    let isUp = translation.height < 0
                    isUp ? up() : down()
                }
        )
    }
}
