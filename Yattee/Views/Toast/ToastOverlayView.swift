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
    /// 0 for the window's own overlay, 1 and up inside presented sheets.
    var depth: Int = 0

    private var toastManager: ToastManager? {
        appEnvironment?.toastManager
    }

    /// Toasts filtered by scope, shown only by the top-most overlay
    private var scopedToasts: [Toast] {
        guard let toastManager, toastManager.topOverlayDepth(for: scope) == depth else { return [] }
        return toastManager.toasts(for: scope)
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(scopedToasts) { toast in
                ToastCardView(
                    toast: toast,
                    onDismiss: {
                        toastManager?.dismiss(id: toast.id)
                    },
                    onAction: toast.action?.handler,
                    onDragBegan: {
                        toastManager?.pauseAutoDismiss(id: toast.id)
                    },
                    onDragCancelled: {
                        toastManager?.resumeAutoDismiss(id: toast.id)
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, topPadding)
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: scopedToasts.count)
        .onAppear { toastManager?.registerOverlay(scope: scope, depth: depth) }
        .onDisappear { toastManager?.unregisterOverlay(scope: scope, depth: depth) }
    }

    private var topPadding: CGFloat {
        #if os(iOS)
        // Sheets start below the status bar
        if depth > 0 { return 16 }
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

    /// Adds a toast overlay to a presented sheet, which takes over its scope's
    /// toasts from the overlays underneath while it is up.
    func sheetToastOverlay(scope: ToastScope, depth: Int) -> some View {
        overlay(alignment: .top) {
            ToastOverlayView(scope: scope, depth: depth)
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
