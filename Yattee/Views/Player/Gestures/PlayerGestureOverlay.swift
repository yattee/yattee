//
//  PlayerGestureOverlay.swift
//  Yattee
//
//  SwiftUI overlay for handling player gestures.
//

#if os(iOS)
import SwiftUI
import UIKit

/// Overlay view that handles tap and seek gestures on the player.
struct PlayerGestureOverlay: View {
    let settings: GesturesSettings
    let isActive: Bool
    let isSeekable: Bool
    let onTapAction: (TapGestureAction, TapZonePosition) -> Void
    let onSingleTap: () -> Void
    let onSeekGestureStarted: () -> Void
    let onSeekGestureChanged: (CGFloat) -> Void
    let onSeekGestureEnded: (CGFloat) -> Void
    /// Returns true if a pinch gesture is currently active (blocks seek gesture).
    var isPinchGestureActive: (() -> Bool)? = nil
    /// Returns true if panel drag is active (blocks seek gesture).
    var isPanelDragging: (() -> Bool)? = nil

    var body: some View {
        GeometryReader { geometry in
            GestureRecognizerView(
                settings: settings,
                bounds: CGRect(origin: .zero, size: geometry.size),
                isActive: isActive,
                isSeekable: isSeekable,
                onDoubleTap: { position in
                    if let config = settings.tapGestures.configuration(for: position) {
                        onTapAction(config.action, position)
                    }
                },
                onSingleTap: onSingleTap,
                onSeekGestureStarted: onSeekGestureStarted,
                onSeekGestureChanged: onSeekGestureChanged,
                onSeekGestureEnded: onSeekGestureEnded,
                isPinchGestureActive: isPinchGestureActive,
                isPanelDragging: isPanelDragging
            )
        }
        // Always allow hit testing - single tap to toggle controls should work
        // regardless of whether controls are visible. The coordinator handles
        // disabling double-tap gestures when isActive is false.
        .allowsHitTesting(true)
    }
}

// MARK: - UIViewRepresentable

private struct GestureRecognizerView: UIViewRepresentable {
    let settings: GesturesSettings
    let bounds: CGRect
    let isActive: Bool
    let isSeekable: Bool
    let onDoubleTap: (TapZonePosition) -> Void
    let onSingleTap: () -> Void
    let onSeekGestureStarted: () -> Void
    let onSeekGestureChanged: (CGFloat) -> Void
    let onSeekGestureEnded: (CGFloat) -> Void
    var isPinchGestureActive: (() -> Bool)? = nil
    var isPanelDragging: (() -> Bool)? = nil

    func makeCoordinator() -> PlayerGestureCoordinator {
        PlayerGestureCoordinator(
            tapSettings: settings.tapGestures,
            seekSettings: settings.seekGesture
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let coordinator = context.coordinator
        coordinator.isActive = isActive
        coordinator.isSeekable = isSeekable
        coordinator.onDoubleTap = onDoubleTap
        coordinator.onSingleTap = onSingleTap
        coordinator.onSeekGestureStarted = onSeekGestureStarted
        coordinator.onSeekGestureChanged = onSeekGestureChanged
        coordinator.onSeekGestureEnded = onSeekGestureEnded
        coordinator.isPinchGestureActive = isPinchGestureActive
        coordinator.isPanelDragging = isPanelDragging
        coordinator.attach(to: view)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.tapSettings = settings.tapGestures
        coordinator.seekSettings = settings.seekGesture
        coordinator.bounds = bounds
        coordinator.isActive = isActive
        coordinator.isSeekable = isSeekable

        // Update callbacks
        coordinator.onDoubleTap = onDoubleTap
        coordinator.onSingleTap = onSingleTap
        coordinator.onSeekGestureStarted = onSeekGestureStarted
        coordinator.onSeekGestureChanged = onSeekGestureChanged
        coordinator.onSeekGestureEnded = onSeekGestureEnded
        coordinator.isPinchGestureActive = isPinchGestureActive
        coordinator.isPanelDragging = isPanelDragging
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: PlayerGestureCoordinator) {
        coordinator.detach()
    }
}
#endif
