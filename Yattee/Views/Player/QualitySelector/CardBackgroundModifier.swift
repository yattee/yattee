//
//  CardBackgroundModifier.swift
//  Yattee
//
//  Reusable card background modifier for grouped list items.
//

import SwiftUI

/// Applies platform-appropriate card background with rounded corners.
///
/// Uses `ListBackgroundStyle.card` for consistent appearance across platforms.
struct CardBackgroundModifier: ViewModifier {
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .background(ListBackgroundStyle.card.color)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    /// Applies card background styling used in grouped lists.
    ///
    /// - Parameter cornerRadius: The corner radius for the rounded rectangle. Defaults to 10.
    /// - Returns: A view with card background applied.
    func cardBackground(cornerRadius: CGFloat = 10) -> some View {
        modifier(CardBackgroundModifier(cornerRadius: cornerRadius))
    }
}
