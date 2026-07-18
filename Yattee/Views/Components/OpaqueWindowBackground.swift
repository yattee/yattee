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
struct OpaqueWindowBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content
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
