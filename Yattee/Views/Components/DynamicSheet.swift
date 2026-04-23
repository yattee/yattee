//
//  DynamicSheet.swift
//  Yattee
//
//  Primitives for dynamic sheet height based on calculated content size.
//  For List/Form content that doesn't have intrinsic size.
//

import SwiftUI

// MARK: - Environment Key for Sheet Height

private struct SheetHeightKey: EnvironmentKey {
    static let defaultValue: Binding<CGFloat>? = nil
}

extension EnvironmentValues {
    /// Binding to report calculated content height to the sheet container.
    var sheetContentHeight: Binding<CGFloat>? {
        get { self[SheetHeightKey.self] }
        set { self[SheetHeightKey.self] = newValue }
    }
}

// MARK: - Dynamic Sheet Container

/// A sheet container that adjusts detents based on reported content height.
/// Child views should write to `sheetContentHeight` environment to report their size.
struct DynamicSheetContainer<Content: View>: View {
    var animation: Animation = .smooth(duration: 0.35)
    @ViewBuilder var content: Content

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        content
            .environment(\.sheetContentHeight, Binding(
                get: { contentHeight },
                set: { newValue in
                    if contentHeight == 0 {
                        contentHeight = newValue
                    } else {
                        withAnimation(animation) {
                            contentHeight = newValue
                        }
                    }
                }
            ))
            #if os(iOS)
            .modifier(SheetHeightModifier(height: contentHeight))
            #endif
    }
}

// MARK: - Animatable Sheet Height Modifier

/// ViewModifier that applies presentation detents with smooth animation.
/// Conforms to Animatable so SwiftUI can interpolate height changes.
private struct SheetHeightModifier: ViewModifier, Animatable {
    var height: CGFloat

    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    func body(content: Content) -> some View {
        content
            .presentationDetents(height == 0 ? [.medium, .large] : [.height(height), .large])
    }
}
