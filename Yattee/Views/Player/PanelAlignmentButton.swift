//
//  PanelAlignmentButton.swift
//  Yattee
//
//  Floating alignment toggle button for the details panel in wide layout.
//

import SwiftUI

#if os(iOS) || os(macOS)

/// A floating button that toggles the panel between left and right sides.
/// Mirrors the style of PanelPinButton: 36pt glass circle, same shadow and haptic.
struct PanelAlignmentButton: View {
    let panelSide: FloatingPanelSide
    let onAlignmentToggle: () -> Void

    /// Whether the drag handle is currently active (being dragged or hovered).
    @Binding var isDragHandleActive: Bool

    @Environment(\.appEnvironment) private var appEnvironment

    /// Button diameter
    private static let buttonSize: CGFloat = 36

    var body: some View {
        Button {
            triggerHaptic()
            onAlignmentToggle()
        } label: {
            Image(systemName: panelSide == .left ? "arrow.right" : "arrow.left")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .glassBackground(.regular, in: .circle, fallback: .thinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(panelSide == .left
            ? String(localized: "wideLayoutPanel.alignmentButton.moveRight")
            : String(localized: "wideLayoutPanel.alignmentButton.moveLeft"))
    }

    // MARK: - Haptic Feedback

    private func triggerHaptic() {
        #if os(iOS)
        appEnvironment?.settingsManager.triggerHapticFeedback(for: .subscribeButton)
        #endif
    }
}

#endif
