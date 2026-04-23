//
//  GlassBackground.swift
//  Yattee
//
//  Adaptive glass background that uses liquid glass on iOS 26+ and falls back to materials on older versions.
//

import SwiftUI

// MARK: - Glass Style

/// Style options for the glass background effect
enum GlassStyle {
    /// Clear glass with minimal blur - subtle transparency
    case clear
    /// Regular glass with standard blur and reflection
    case regular
    /// Tinted glass with a color overlay
    case tinted(Color)
}

// MARK: - Glass Shape

/// Shape options for the glass background
enum GlassShape {
    /// Rectangle with corner radius
    case rect(cornerRadius: CGFloat)
    /// Capsule shape
    case capsule
    /// Circle shape
    case circle
}

// MARK: - Fallback Material

/// Material to use on iOS versions before 26
enum GlassFallbackMaterial {
    case ultraThinMaterial
    case thinMaterial
    case regularMaterial
    case thickMaterial
    case ultraThickMaterial
}

// MARK: - Glass Background Modifier

/// A view modifier that applies liquid glass effect on iOS 26+ and falls back to materials on older versions
struct GlassBackgroundModifier: ViewModifier {
    let style: GlassStyle
    let shape: GlassShape
    let fallbackMaterial: GlassFallbackMaterial
    let colorScheme: ColorScheme?

    init(
        style: GlassStyle = .clear,
        shape: GlassShape = .rect(cornerRadius: 12),
        fallbackMaterial: GlassFallbackMaterial = .ultraThinMaterial,
        colorScheme: ColorScheme? = nil
    ) {
        self.style = style
        self.shape = shape
        self.fallbackMaterial = fallbackMaterial
        self.colorScheme = colorScheme
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            content.modifier(LiquidGlassModifier(style: style, shape: shape, colorScheme: colorScheme))
        } else {
            content.modifier(FallbackGlassModifier(shape: shape, material: fallbackMaterial))
        }
        #else
        // macOS doesn't have glassEffect, always use fallback material
        content.modifier(FallbackGlassModifier(shape: shape, material: fallbackMaterial))
        #endif
    }
}

// MARK: - iOS 26+ Liquid Glass

#if os(iOS)
@available(iOS 26.0, *)
private struct LiquidGlassModifier: ViewModifier {
    let style: GlassStyle
    let shape: GlassShape
    let colorScheme: ColorScheme?

    func body(content: Content) -> some View {
        switch shape {
        case .rect(let cornerRadius):
            applyGlassEffect(to: content, shape: .rect(cornerRadius: cornerRadius))
        case .capsule:
            applyGlassEffect(to: content, shape: .capsule)
        case .circle:
            applyGlassEffect(to: content, shape: .circle)
        }
    }

    @ViewBuilder
    private func applyGlassEffect<S: Shape>(to content: Content, shape: S) -> some View {
        if let scheme = colorScheme {
            switch style {
            case .clear:
                content.glassEffect(.clear, in: shape).environment(\.colorScheme, scheme)
            case .regular:
                content.glassEffect(.regular, in: shape).environment(\.colorScheme, scheme)
            case .tinted(let color):
                content.glassEffect(.regular.tint(color), in: shape).environment(\.colorScheme, scheme)
            }
        } else {
            switch style {
            case .clear:
                content.glassEffect(.clear, in: shape)
            case .regular:
                content.glassEffect(.regular, in: shape)
            case .tinted(let color):
                content.glassEffect(.regular.tint(color), in: shape)
            }
        }
    }
}
#endif

// MARK: - Fallback for older iOS / macOS

private struct FallbackGlassModifier: ViewModifier {
    let shape: GlassShape
    let material: GlassFallbackMaterial

    func body(content: Content) -> some View {
        switch shape {
        case .rect(let cornerRadius):
            content
                .background(materialBackground)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        case .capsule:
            content
                .background(materialBackground)
                .clipShape(Capsule())
        case .circle:
            content
                .background(materialBackground)
                .clipShape(Circle())
        }
    }

    @ViewBuilder
    private var materialBackground: some View {
        switch material {
        case .ultraThinMaterial:
            Rectangle().fill(.ultraThinMaterial)
        case .thinMaterial:
            Rectangle().fill(.thinMaterial)
        case .regularMaterial:
            Rectangle().fill(.regularMaterial)
        case .thickMaterial:
            Rectangle().fill(.thickMaterial)
        case .ultraThickMaterial:
            Rectangle().fill(.ultraThickMaterial)
        }
    }
}

// MARK: - View Extension

extension View {
    /// Applies a glass background effect that adapts to the platform
    /// - Parameters:
    ///   - style: The glass style (clear, regular, or tinted)
    ///   - shape: The shape of the glass background
    ///   - fallbackMaterial: The material to use on iOS < 26
    ///   - colorScheme: Optional color scheme to force (affects glass appearance on iOS 26+)
    /// - Returns: A view with the glass background applied
    func glassBackground(
        _ style: GlassStyle = .clear,
        in shape: GlassShape = .rect(cornerRadius: 12),
        fallback: GlassFallbackMaterial = .ultraThinMaterial,
        colorScheme: ColorScheme? = nil
    ) -> some View {
        modifier(GlassBackgroundModifier(style: style, shape: shape, fallbackMaterial: fallback, colorScheme: colorScheme))
    }
}
