//
//  View+SoftScrollEdgeEffect.swift
//  Yattee
//
//  iOS 27 changed the default scroll edge effect style from soft to hard,
//  which draws a sharp dividing line under the toolbar. Views that extend
//  a banner or gradient beneath the toolbar (channel header, video info)
//  need the soft style so the artwork stays cleanly visible.
//

import SwiftUI

extension View {
    /// Forces the soft (blur/fade) scroll edge effect on the top edge
    /// for scroll views in this hierarchy. No-op before iOS 26/macOS 26.
    @ViewBuilder
    func softTopScrollEdgeEffect() -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}
