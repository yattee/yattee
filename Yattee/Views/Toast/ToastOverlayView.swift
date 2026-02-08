//
//  ToastOverlayView.swift
//  Yattee
//
//  Overlay container for displaying toast notifications at the top of the screen.
//

import SwiftUI

/// Overlay that displays toast notifications at the top of the screen.
struct ToastOverlayView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    /// The scope of toasts to display in this overlay.
    let scope: ToastScope

    private var toastManager: ToastManager? {
        appEnvironment?.toastManager
    }

    /// Toasts filtered by scope
    private var scopedToasts: [Toast] {
        toastManager?.toasts(for: scope) ?? []
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(scopedToasts) { toast in
                ToastCardView(
                    toast: toast,
                    onDismiss: {
                        toastManager?.dismiss(id: toast.id)
                    },
                    onAction: toast.action?.handler
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                #if !os(tvOS)
                .gesture(swipeGesture(for: toast))
                #endif
            }
        }
        .padding(.top, topPadding)
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: scopedToasts.count)
    }

    private var topPadding: CGFloat {
        #if os(iOS)
        // In player scope (sheet), only need minimal padding since safe area is handled by sheet
        // In main scope, account for Dynamic Island / notch
        return scope == .player ? 8 : 60
        #elseif os(macOS)
        return 16
        #elseif os(tvOS)
        // TV safe area
        return 60
        #endif
    }

    #if !os(tvOS)
    private func swipeGesture(for toast: Toast) -> some Gesture {
        DragGesture()
            .onEnded { value in
                // Swipe up to dismiss
                if value.translation.height < -50 {
                    toastManager?.dismiss(id: toast.id)
                }
            }
    }
    #endif
}

// MARK: - View Extension

extension View {
    /// Adds a toast overlay for the main window scope.
    func toastOverlay() -> some View {
        overlay(alignment: .top) {
            ToastOverlayView(scope: .main)
        }
    }

    /// Adds a toast overlay for the player scope.
    func playerToastOverlay() -> some View {
        overlay(alignment: .top) {
            ToastOverlayView(scope: .player)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()

        Text("Main Content")
    }
    .toastOverlay()
    .appEnvironment(.preview)
}
