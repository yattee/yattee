//
//  TVFullScreenCoverBackground.swift
//  Yattee
//
//  Scheme-adaptive opaque background for tvOS full screen covers.
//

import SwiftUI

#if os(tvOS)
/// tvOS full screen covers have a transparent background, letting the view
/// below leak through, so they need an explicit opaque fill. A hardcoded
/// black makes primary (black) text invisible under the light color scheme,
/// so the fill follows the scheme instead.
struct TVFullScreenCoverBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                (colorScheme == .dark ? Color.black : Color(white: 0.92))
                    .ignoresSafeArea()
            )
    }
}
#endif

extension View {
    /// Gives a tvOS full screen cover an opaque, color-scheme-appropriate
    /// background. No-op on other platforms.
    @ViewBuilder
    func tvFullScreenCoverBackground() -> some View {
        #if os(tvOS)
        modifier(TVFullScreenCoverBackgroundModifier())
        #else
        self
        #endif
    }
}
