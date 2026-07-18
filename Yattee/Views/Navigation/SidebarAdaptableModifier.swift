//
//  SidebarAdaptableModifier.swift
//  Yattee
//
//  Navigation-related view modifiers.
//

import SwiftUI

// MARK: - Sidebar Adaptable Modifier

#if os(iOS)
struct SidebarAdaptableModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.tabViewStyle(.sidebarAdaptable)
    }
}

extension View {
    /// Applies sidebar adaptable style.
    func sidebarAdaptable() -> some View {
        modifier(SidebarAdaptableModifier())
    }
}
#endif
