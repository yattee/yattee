//
//  TVRemoteHoldSeekObserver.swift
//  Yattee
//
//  Press-and-hold continuous seeking. Implemented by attaching a pair of
//  UILongPressGestureRecognizer instances (one per arrow press type) to
//  the UIWindow, so they intercept Siri Remote dpad presses regardless of
//  which SwiftUI view is currently focused. SwiftUI's `.onMoveCommand`
//  continues to receive the discrete "press" event for the first step;
//  our recognizer kicks in after 400 ms to drive continuous seeking until
//  the user releases.
//

#if os(tvOS)
import Combine
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Routes the d-pad direction to the appropriate seek action while held.
typealias TVRemoteHoldSeekTick = @Sendable @MainActor (_ forward: Bool, _ stepSeconds: Int) -> Void

/// Invisible SwiftUI view that, while in the hierarchy, wires window-level
/// long-press recognizers for left/right arrow press types.
struct TVRemoteHoldSeekOverlay: UIViewRepresentable {
    let isActive: Bool
    let onTick: TVRemoteHoldSeekTick

    @MainActor
    func makeCoordinator() -> Coordinator {
        Coordinator(onTick: onTick)
    }

    @MainActor
    func makeUIView(context: Context) -> UIView {
        let view = TVRemoteHoldSeekHostView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    @MainActor
    func updateUIView(_: UIView, context: Context) {
        context.coordinator.update(onTick: onTick, isActive: isActive)
    }

    static func dismantleUIView(_: UIView, coordinator: Coordinator) {
        coordinator.detachFromWindow()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTick: TVRemoteHoldSeekTick

        private static let initialDelay: TimeInterval = 0.4
        private static let tickInterval: TimeInterval = 0.25
        private static let mediumThreshold: TimeInterval = 1.5
        private static let fastThreshold: TimeInterval = 3.0
        private static let baseStep = 10
        private static let mediumStep = 20
        private static let fastStep = 30

        private weak var attachedWindow: UIWindow?
        private var leftRecognizer: RemoteArrowPressRecognizer?
        private var rightRecognizer: RemoteArrowPressRecognizer?

        private var heldForward: Bool?
        private var holdStart: Date?
        private var initialDelayWorkItem: DispatchWorkItem?
        private var tickTimer: Timer?
        private var active = true

        init(onTick: @escaping TVRemoteHoldSeekTick) {
            self.onTick = onTick
        }

        func update(onTick: @escaping TVRemoteHoldSeekTick, isActive: Bool) {
            if active != isActive {
                active = isActive
                if !isActive { cancelHold() }
                leftRecognizer?.isEnabled = isActive
                rightRecognizer?.isEnabled = isActive
            }
            self.onTick = onTick
        }

        func attach(to window: UIWindow) {
            if attachedWindow === window { return }
            detachFromWindow()
            attachedWindow = window

            let left = makeRecognizer(pressType: .leftArrow, action: #selector(handleLeft(_:)))
            let right = makeRecognizer(pressType: .rightArrow, action: #selector(handleRight(_:)))
            window.addGestureRecognizer(left)
            window.addGestureRecognizer(right)
            leftRecognizer = left
            rightRecognizer = right
        }

        private func makeRecognizer(pressType: UIPress.PressType, action: Selector) -> RemoteArrowPressRecognizer {
            let recognizer = RemoteArrowPressRecognizer(pressType: pressType, target: self, action: action)
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }

        func detachFromWindow() {
            if let leftRecognizer, let attachedWindow {
                attachedWindow.removeGestureRecognizer(leftRecognizer)
            }
            if let rightRecognizer, let attachedWindow {
                attachedWindow.removeGestureRecognizer(rightRecognizer)
            }
            leftRecognizer = nil
            rightRecognizer = nil
            attachedWindow = nil
            cancelHold()
        }

        @objc func handleLeft(_ gr: UIGestureRecognizer) {
            handle(gr, forward: false)
        }

        @objc func handleRight(_ gr: UIGestureRecognizer) {
            handle(gr, forward: true)
        }

        private func handle(_ gr: UIGestureRecognizer, forward: Bool) {
            switch gr.state {
            case .began:
                // A new press of any direction always restarts the hold —
                // if a previous .ended was dropped by UIKit, this catches
                // it and resets the watchdog cleanly.
                cancelHold()
                beginHold(forward: forward)
            case .ended, .cancelled, .failed:
                if heldForward == forward {
                    cancelHold()
                }
            default:
                break
            }
        }

        private func beginHold(forward: Bool) {
            heldForward = forward
            holdStart = Date()
            // DispatchQueue.main and Timer.scheduledTimer always fire on
            // the main thread, but neither closure is statically isolated
            // to MainActor — `assumeIsolated` is the cheap, allocation-free
            // bridge.
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.startTickTimer() }
            }
            initialDelayWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.initialDelay, execute: work)
        }

        private func startTickTimer() {
            guard heldForward != nil, tickTimer == nil else { return }
            emitTick()
            let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.emitTick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            tickTimer = timer
        }

        private func emitTick() {
            guard let forward = heldForward, let holdStart else { return }
            // Defensive check: if UIKit transitioned the tracked press out
            // of an active phase but failed to call pressesEnded on the
            // recognizer, the press's own phase still reflects reality.
            // Catch that here so the timer doesn't run away.
            let activeRecognizer = forward ? rightRecognizer : leftRecognizer
            if let phase = activeRecognizer?.trackedPressPhase,
               phase != .began, phase != .changed, phase != .stationary
            {
                cancelHold()
                return
            }
            let elapsed = Date().timeIntervalSince(holdStart)
            let step: Int
            if elapsed >= Self.fastThreshold {
                step = Self.fastStep
            } else if elapsed >= Self.mediumThreshold {
                step = Self.mediumStep
            } else {
                step = Self.baseStep
            }
            onTick(forward, step)
        }

        private func cancelHold() {
            initialDelayWorkItem?.cancel()
            initialDelayWorkItem = nil
            tickTimer?.invalidate()
            tickTimer = nil
            heldForward = nil
            holdStart = nil
        }

        // Allow these recognizers to coexist with everything else (focus
        // engine taps, SwiftUI gestures, etc.) — we only OBSERVE the press
        // duration; we do not want to swallow events.
        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldReceive _: UIPress
        ) -> Bool {
            true
        }
    }
}

/// Custom gesture recognizer that observes a single arrow press type.
/// Overrides the press hooks directly because `UILongPressGestureRecognizer`
/// with `allowedPressTypes` does not always fire when a focused view
/// consumes the press.
private final class RemoteArrowPressRecognizer: UIGestureRecognizer {
    let pressType: UIPress.PressType
    private var trackedPress: UIPress?

    /// Exposes the live phase of the press currently being tracked, so
    /// callers can sanity-check whether UIKit still considers the press
    /// active even when `pressesEnded` was never delivered.
    var trackedPressPhase: UIPress.Phase? { trackedPress?.phase }

    init(pressType: UIPress.PressType, target: Any?, action: Selector?) {
        self.pressType = pressType
        super.init(target: target, action: action)
        allowedPressTypes = [NSNumber(value: pressType.rawValue)]
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        super.pressesBegan(presses, with: event)
        guard trackedPress == nil else { return }
        if let match = presses.first(where: { $0.type == pressType }) {
            trackedPress = match
            state = .began
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        super.pressesEnded(presses, with: event)
        if let trackedPress, presses.contains(trackedPress) {
            self.trackedPress = nil
            state = .ended
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        super.pressesCancelled(presses, with: event)
        if let trackedPress, presses.contains(trackedPress) {
            self.trackedPress = nil
            state = .cancelled
        }
    }

    override func reset() {
        super.reset()
        trackedPress = nil
    }
}

/// Bridge view that, on `didMoveToWindow`, hands the window to its
/// coordinator so the gesture recognizers can be installed at the
/// window level.
private final class TVRemoteHoldSeekHostView: UIView {
    weak var coordinator: TVRemoteHoldSeekOverlay.Coordinator?

    override var canBecomeFocused: Bool { false }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window {
            coordinator?.attach(to: window)
        } else {
            coordinator?.detachFromWindow()
        }
    }
}
#endif
