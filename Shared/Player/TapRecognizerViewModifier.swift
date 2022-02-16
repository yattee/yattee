import SwiftUI

struct TapRecognizerViewModifier: ViewModifier {
    @State private var singleTapIsTaped: Bool = .init()

    var tapSensitivity: Double
    var singleTapAction: () -> Void
    var doubleTapAction: () -> Void

    init(tapSensitivity: Double, singleTapAction: @escaping () -> Void, doubleTapAction: @escaping () -> Void) {
        self.tapSensitivity = tapSensitivity
        self.singleTapAction = singleTapAction
        self.doubleTapAction = doubleTapAction
    }

    func body(content: Content) -> some View {
        content.gesture(simultaneouslyGesture)
    }

    private var singleTapGesture: some Gesture {
        TapGesture(count: 1).onEnded {
            singleTapIsTaped = true

            DispatchQueue.main.asyncAfter(deadline: .now() + tapSensitivity) {
                if singleTapIsTaped {
                    singleTapAction()
                }
            }
        }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2).onEnded {
            singleTapIsTaped = false
            doubleTapAction()
        }
    }

    private var simultaneouslyGesture: some Gesture {
        singleTapGesture.simultaneously(with: doubleTapGesture)
    }
}

extension View {
    func tapRecognizer(tapSensitivity: Double, singleTapAction: @escaping () -> Void, doubleTapAction: @escaping () -> Void) -> some View {
        modifier(TapRecognizerViewModifier(tapSensitivity: tapSensitivity, singleTapAction: singleTapAction, doubleTapAction: doubleTapAction))
    }
}
