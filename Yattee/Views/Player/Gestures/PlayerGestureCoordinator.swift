//
//  PlayerGestureCoordinator.swift
//  Yattee
//
//  UIKit gesture recognizer coordinator for player gestures.
//

#if os(iOS)
import UIKit

/// Coordinates UIKit gesture recognizers for player tap and seek gestures.
final class PlayerGestureCoordinator: NSObject, UIGestureRecognizerDelegate {
    // MARK: - Configuration

    var tapSettings: TapGesturesSettings
    var seekSettings: SeekGestureSettings
    var bounds: CGRect = .zero
    /// Whether gesture actions (double-tap, seek) should be active.
    /// Single tap to toggle controls visibility always works regardless of this flag.
    var isActive: Bool = true
    /// Whether the content is seekable (false for live streams).
    var isSeekable: Bool = true

    // MARK: - Callbacks

    var onDoubleTap: ((TapZonePosition) -> Void)?
    var onSingleTap: (() -> Void)?
    /// Returns true if a pinch gesture is currently active (blocks seek gesture).
    var isPinchGestureActive: (() -> Bool)?
    /// Returns true if panel drag is active (blocks seek gesture).
    var isPanelDragging: (() -> Bool)?

    /// Called when seek gesture is recognized (after activation threshold).
    var onSeekGestureStarted: (() -> Void)?
    /// Called during seek gesture with cumulative horizontal translation.
    var onSeekGestureChanged: ((CGFloat) -> Void)?
    /// Called when seek gesture ends with final horizontal translation.
    var onSeekGestureEnded: ((CGFloat) -> Void)?

    // MARK: - Gesture Recognizers

    private var doubleTapRecognizer: UITapGestureRecognizer?
    private var singleTapRecognizer: UITapGestureRecognizer?
    private var panRecognizer: UIPanGestureRecognizer?

    // MARK: - Seek Gesture State

    /// Whether the current pan has been recognized as a seek gesture.
    private var isRecognizedAsSeekGesture = false
    /// Starting translation when seek gesture was recognized.
    private var seekGestureStartTranslation: CGPoint = .zero

    // MARK: - Initialization

    init(tapSettings: TapGesturesSettings, seekSettings: SeekGestureSettings = .default) {
        self.tapSettings = tapSettings
        self.seekSettings = seekSettings
        super.init()
    }

    // MARK: - Setup

    /// Attaches gesture recognizers to the view.
    func attach(to view: UIView) {
        detach()

        // Double-tap recognizer
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        view.addGestureRecognizer(doubleTap)
        doubleTapRecognizer = doubleTap

        // Single-tap recognizer (requires double-tap to fail)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        singleTap.delegate = self
        view.addGestureRecognizer(singleTap)
        singleTapRecognizer = singleTap

        // Pan recognizer for seek gesture
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
        panRecognizer = pan

        // Single tap should require pan to fail for better UX
        // This prevents single tap from firing if user starts dragging
        singleTap.require(toFail: pan)

        // Update double-tap timing
        updateDoubleTapTiming()
    }

    /// Removes gesture recognizers from the view.
    func detach() {
        if let recognizer = doubleTapRecognizer {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }
        if let recognizer = singleTapRecognizer {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }
        if let recognizer = panRecognizer {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }

        doubleTapRecognizer = nil
        singleTapRecognizer = nil
        panRecognizer = nil
    }

    /// Updates the double-tap timing window.
    func updateDoubleTapTiming() {
        // iOS doesn't have a direct API for this, but we can use
        // the delay for single-tap via the require(toFail:) mechanism
        // The actual timing is controlled by iOS based on the interval
    }

    // MARK: - Gesture Handlers

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard isActive, tapSettings.isEnabled else { return }

        let location = recognizer.location(in: recognizer.view)
        if let zone = TapZoneCalculator.zone(for: location, in: bounds, layout: tapSettings.layout) {
            onDoubleTap?(zone)
        }
    }

    @objc private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
        // Single tap toggles controls visibility
        onSingleTap?()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: recognizer.view)

        switch recognizer.state {
        case .began:
            // Reset state at the start of each pan
            isRecognizedAsSeekGesture = false
            seekGestureStartTranslation = .zero

        case .changed:
            // Check if we should recognize this as a seek gesture
            if !isRecognizedAsSeekGesture {
                let translationSize = CGSize(width: translation.x, height: translation.y)
                if SeekGestureCalculator.isHorizontalMovement(translation: translationSize) {
                    // Recognize as seek gesture
                    isRecognizedAsSeekGesture = true
                    seekGestureStartTranslation = translation
                    onSeekGestureStarted?()
                }
            }

            // If recognized, send updates
            if isRecognizedAsSeekGesture {
                let horizontalDelta = translation.x - seekGestureStartTranslation.x
                onSeekGestureChanged?(horizontalDelta)
            }

        case .ended, .cancelled:
            if isRecognizedAsSeekGesture {
                let horizontalDelta = translation.x - seekGestureStartTranslation.x
                onSeekGestureEnded?(horizontalDelta)
            }
            // Reset state
            isRecognizedAsSeekGesture = false
            seekGestureStartTranslation = .zero

        default:
            break
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Single tap always allowed - it toggles controls visibility
        if gestureRecognizer == singleTapRecognizer {
            return true
        }

        // Double-tap only allowed when isActive (controls hidden) and tap gestures enabled
        if gestureRecognizer == doubleTapRecognizer {
            return isActive && tapSettings.isEnabled
        }

        // Pan gesture only allowed when isActive, seek enabled, content is seekable, and pinch not active
        if gestureRecognizer == panRecognizer {
            // Block seek gesture if pinch gesture is active
            if isPinchGestureActive?() == true { return false }
            // Block seek gesture if panel drag is active
            if isPanelDragging?() == true { return false }
            return isActive && seekSettings.isEnabled && isSeekable
        }

        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Don't allow simultaneous recognition with other gestures
        // to avoid conflicts with existing player gestures
        false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Single tap requires double tap to fail
        if gestureRecognizer == singleTapRecognizer && otherGestureRecognizer == doubleTapRecognizer {
            return true
        }
        // Single tap requires pan to fail
        if gestureRecognizer == singleTapRecognizer && otherGestureRecognizer == panRecognizer {
            return true
        }
        return false
    }
}
#endif
