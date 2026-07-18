//
//  OverscrollGestureHandler.swift
//  Yattee
//
//  UIKit gesture handler for detecting overscroll pull-down gestures on UIScrollView.
//  When user pulls down at scroll top, disables bounce and forwards drag events for smooth
//  panel collapse animation.
//

#if os(iOS)
import UIKit

/// Coordinates overscroll detection on a UIScrollView, calling back during pull-down gestures
/// when the scroll is at top. Disables bounce during the gesture to allow smooth animation.
final class OverscrollGestureHandler: NSObject, UIGestureRecognizerDelegate {
    // MARK: - Properties

    weak var scrollView: UIScrollView?
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: ((CGFloat, CGFloat) -> Void)?

    /// Whether we're currently tracking an overscroll gesture
    private var isTracking = false

    /// The pan gesture recognizer we add to the scroll view
    private var panRecognizer: UIPanGestureRecognizer?

    // MARK: - Setup

    /// Attaches the pan gesture recognizer to the scroll view.
    func attach(to scrollView: UIScrollView) {
        detach()

        self.scrollView = scrollView

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        scrollView.addGestureRecognizer(pan)
        panRecognizer = pan
    }

    /// Removes the pan gesture recognizer from the scroll view.
    func detach() {
        if let recognizer = panRecognizer, let view = recognizer.view {
            view.removeGestureRecognizer(recognizer)
        }
        panRecognizer = nil
        scrollView = nil
        isTracking = false
    }

    // MARK: - Gesture Handling

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let scrollView else { return }

        switch gesture.state {
        case .began:
            // Start tracking - disable bounce so we can control the movement
            isTracking = true
            scrollView.bounces = false

        case .changed:
            let translation = gesture.translation(in: gesture.view)
            // Only forward positive (pull down) translations
            if translation.y > 0 {
                onDragChanged?(translation.y)
            }

        case .ended, .cancelled:
            // Re-enable bounce
            scrollView.bounces = true
            isTracking = false

            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            // Calculate predicted end position
            let decelerationTime: CGFloat = 0.3
            let predicted = translation.y + velocity.y * decelerationTime

            onDragEnded?(translation.y, predicted)

        default:
            break
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
              let scrollView else {
            return false
        }

        let velocity = pan.velocity(in: pan.view)

        // Only begin if:
        // 1. Scroll view is at top (contentOffset.y <= 0)
        // 2. User is pulling down (velocity.y > 0)
        // 3. Vertical movement is dominant (to not interfere with horizontal scrolling)
        let isAtTop = scrollView.contentOffset.y <= 0
        let isPullingDown = velocity.y > 0
        let isVerticalDominant = abs(velocity.y) > abs(velocity.x)

        return isAtTop && isPullingDown && isVerticalDominant
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Don't allow simultaneous recognition - we take over when overscrolling
        false
    }
}
#endif
