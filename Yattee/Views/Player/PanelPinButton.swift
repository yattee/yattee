//
//  PanelPinButton.swift
//  Yattee
//
//  Floating pin button for the details panel in wide layout.
//

import SwiftUI

#if os(iOS) || os(macOS)

/// A floating pin button that appears on the divider edge between player and panel.
/// Features auto-hide behavior with 3s timer, reappearing on drag handle interaction.
struct PanelPinButton: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let isPinned: Bool
    let panelSide: FloatingPanelSide
    let onPinToggle: () -> Void

    /// Whether the drag handle is currently active (being dragged or hovered).
    @Binding var isDragHandleActive: Bool

    /// Button diameter
    private static let buttonSize: CGFloat = 36

    private var accentColor: Color {
        appEnvironment?.settingsManager.accentColor.color ?? .accentColor
    }

    var body: some View {
        Button {
            triggerHaptic()
            onPinToggle()
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isPinned ? accentColor : .primary)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .glassBackground(.regular, in: .circle, fallback: .thinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPinned
            ? String(localized: "wideLayoutPanel.pinButton.unpin")
            : String(localized: "wideLayoutPanel.pinButton.pin"))
    }

    // MARK: - Haptic Feedback

    private func triggerHaptic() {
        #if os(iOS)
        appEnvironment?.settingsManager.triggerHapticFeedback(for: .subscribeButton)
        #endif
    }
}

#endif
