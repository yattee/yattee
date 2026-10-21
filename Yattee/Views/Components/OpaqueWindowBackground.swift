//
//  OpaqueWindowBackground.swift
//  Yattee
//
//  Unified opaque background for main content views on macOS.
//

import SwiftUI

/// Applies an opaque window background on macOS.
///
/// Without an explicit background, content sits on the translucent window
/// material, which picks up a wallpaper tint (often bluish in dark mode) and
/// clashes with views that draw `windowBackgroundColor` themselves (lists,
/// gradient fades). No-op on other platforms.
///
/// The view is expanded to fill the proposed space first, so content-sized
/// pages (empty states, placeholders, spinners) don't paint only a strip
/// behind themselves while the rest stays on the window material.
struct OpaqueWindowBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        #else
        content
        #endif
    }
}

extension View {
    /// Gives the view an opaque window background on macOS so all main content
    /// views share the same background color. No-op on iOS/tvOS.
    func opaqueWindowBackground() -> some View {
        modifier(OpaqueWindowBackgroundModifier())
    }
}
