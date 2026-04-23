//
//  View+LiquidGlassSheet.swift
//  Yattee
//
//  View modifiers for iOS 26 Liquid Glass morphing sheet transitions.
//

import SwiftUI

// MARK: - Transition Source Modifier (for Views)

/// View modifier that marks a view as the source for a morphing sheet transition.
/// Apply this to a Button inside a ToolbarItem to enable the morphing effect on iOS 26+.
struct LiquidGlassTransitionSourceModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            content
                .matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Sheet Content Modifier (for sheet content)

/// View modifier that applies the zoom navigation transition to sheet content.
/// Apply this to the content inside a .sheet() to complete the morphing effect on iOS 26+.
struct LiquidGlassSheetContentModifier: ViewModifier {
    let sourceID: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            content
                .navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - View Extensions

extension View {
    /// Marks this view as the source for a Liquid Glass morphing sheet transition.
    ///
    /// Apply this modifier to a Button (or other view) that presents a sheet. On iOS 26+,
    /// the sheet will morph from this view when presented.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for the transition (must match the sheet content's sourceID).
    ///   - namespace: A namespace for the matched geometry effect.
    ///
    /// Example:
    /// ```swift
    /// @Namespace private var sheetTransition
    ///
    /// .toolbar {
    ///     ToolbarItem(placement: .primaryAction) {
    ///         Button { showSheet = true } label: {
    ///             Image(systemName: "gear")
    ///         }
    ///         .liquidGlassTransitionSource(id: "settings", in: sheetTransition)
    ///     }
    /// }
    /// ```
    func liquidGlassTransitionSource(
        id: String,
        in namespace: Namespace.ID
    ) -> some View {
        modifier(LiquidGlassTransitionSourceModifier(id: id, namespace: namespace))
    }

    /// Applies the Liquid Glass morphing transition to sheet content.
    ///
    /// Apply this modifier to the content inside a `.sheet()` modifier. On iOS 26+,
    /// the sheet will morph from the matched transition source when presented.
    ///
    /// - Parameters:
    ///   - sourceID: Unique identifier matching the transition source's id.
    ///   - namespace: A namespace for the matched geometry effect (must match the source).
    ///
    /// Example:
    /// ```swift
    /// .sheet(isPresented: $showSheet) {
    ///     SettingsView()
    ///         .liquidGlassSheetContent(sourceID: "settings", in: sheetTransition)
    /// }
    /// ```
    func liquidGlassSheetContent(
        sourceID: String,
        in namespace: Namespace.ID
    ) -> some View {
        modifier(LiquidGlassSheetContentModifier(sourceID: sourceID, namespace: namespace))
    }
}

// MARK: - ToolbarContent Extension

extension ToolbarContent {
    /// Marks this toolbar content as the source for a Liquid Glass morphing sheet transition.
    ///
    /// Apply this modifier to a `ToolbarItem` that presents a sheet. On iOS 26+,
    /// the sheet will morph from this toolbar item when presented.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for the transition (must match the sheet content's sourceID).
    ///   - namespace: A namespace for the matched geometry effect.
    ///
    /// Example:
    /// ```swift
    /// @Namespace private var sheetTransition
    ///
    /// .toolbar {
    ///     ToolbarItem(placement: .primaryAction) {
    ///         Button { showSheet = true } label: {
    ///             Image(systemName: "gear")
    ///         }
    ///     }
    ///     .liquidGlassTransitionSource(id: "settings", in: sheetTransition)
    /// }
    /// ```
    @ToolbarContentBuilder
    func liquidGlassTransitionSource(
        id: String,
        in namespace: Namespace.ID
    ) -> some ToolbarContent {
        #if os(iOS)
        if #available(iOS 26, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
