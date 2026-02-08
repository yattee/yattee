//
//  SwipeGesture.swift
//  Yattee
//
//  Custom pan gesture that filters horizontal swipes to avoid conflicts with ScrollView.
//

import SwiftUI

#if os(iOS)

/// Value passed to gesture callbacks containing translation and velocity.
struct SwipeGestureValue {
    var translation: CGSize = .zero
    var velocity: CGSize = .zero
}

/// Custom pan gesture recognizer that only begins when horizontal velocity exceeds vertical.
/// This prevents conflicts with ScrollView vertical scrolling.
@available(iOS 18, *)
struct SwipeGesture: UIGestureRecognizerRepresentable {
    var onBegan: () -> Void
    var onChange: (SwipeGestureValue) -> Void
    var onEnded: (SwipeGestureValue) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let gesture = UIPanGestureRecognizer()
        gesture.delegate = context.coordinator
        return gesture
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {}

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let state = recognizer.state
        let translation = recognizer.translation(in: recognizer.view).toSize
        let velocity = recognizer.velocity(in: recognizer.view).toSize

        let gestureValue = SwipeGestureValue(translation: translation, velocity: velocity)

        switch state {
        case .began:
            onBegan()
        case .changed:
            onChange(gestureValue)
        case .ended, .cancelled:
            onEnded(gestureValue)
        default:
            break
        }
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Only begin the gesture when horizontal velocity exceeds vertical velocity.
        /// This allows ScrollView to handle vertical scrolling while we handle horizontal swipes.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
                return false
            }

            let velocity = panGesture.velocity(in: panGesture.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}

private extension CGPoint {
    var toSize: CGSize {
        CGSize(width: x, height: y)
    }
}

#endif
