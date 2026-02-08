//
//  TextTruncationEffect.swift
//  Yattee
//
//  Animated text truncation effect with "...more" indicator.
//  Adapted from Balaji Venkatesh's TruncationEffect implementation.
//

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Text {
    /// Applies an animated truncation effect that shows "...more" when collapsed.
    /// - Parameters:
    ///   - length: Number of lines to show when truncated
    ///   - isEnabled: Whether truncation is enabled (false = expanded)
    ///   - animation: Animation to use for expand/collapse transitions
    @ViewBuilder
    func truncationEffect(length: Int, isEnabled: Bool, animation: Animation) -> some View {
        self.modifier(
            TruncationEffectViewModifier(
                length: length,
                isEnabled: isEnabled,
                animation: animation
            )
        )
    }
}

// MARK: - View Modifier

private struct TruncationEffectViewModifier: ViewModifier {
    var length: Int
    var isEnabled: Bool
    var animation: Animation

    @State private var limitedSize: CGSize = .zero
    @State private var fullSize: CGSize = .zero
    @State private var animatedProgress: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .lineLimit(length)
            .opacity(0)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: { newValue in
                limitedSize = newValue
            }
            .frame(height: isExpanded ? fullSize.height : nil)
            .overlay {
                // Full content with animation
                GeometryReader { proxy in
                    let contentSize = proxy.size

                    content
                        .textRenderer(
                            TruncationTextRenderer(
                                length: length,
                                progress: animatedProgress
                            )
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGSize.self) {
                            $0.size
                        } action: { newValue in
                            fullSize = newValue
                        }
                        .frame(
                            width: contentSize.width,
                            height: contentSize.height,
                            alignment: isExpanded ? .leading : .topLeading
                        )
                }
            }
            .contentShape(.rect)
            .onChange(of: isEnabled) { _, newValue in
                withAnimation(animation) {
                    animatedProgress = !newValue ? 1 : 0
                }
            }
            .onAppear {
                // Set initial value without animation
                animatedProgress = !isEnabled ? 1 : 0
            }
    }

    var isExpanded: Bool {
        animatedProgress == 1
    }
}

// MARK: - Text Renderer

@Animatable
private struct TruncationTextRenderer: TextRenderer {
    @AnimatableIgnored var length: Int
    var progress: CGFloat

    /// Minimum number of hidden characters to show "...more" indicator.
    /// If less than this, just show the full text without truncation indicator.
    private let minHiddenCharacters = 10

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let totalLines = layout.count
        let hasExtraLines = totalLines > length

        // Count characters in lines beyond the limit
        let hiddenCharacterCount: Int = {
            guard hasExtraLines else { return 0 }
            var count = 0
            for index in length..<totalLines {
                count += layout[index].flatMap { $0 }.count
            }
            return count
        }()

        // If hidden content is too short, don't show "...more" - just draw normally
        let shouldShowMoreIndicator = hasExtraLines && hiddenCharacterCount >= minHiddenCharacters

        for (index, line) in layout.enumerated() {
            var copyContext = ctx
            if index == length - 1 && shouldShowMoreIndicator {
                drawMoreTextAtEnd(line: line, context: &copyContext)
            } else {
                if index < length {
                    // Draw all visible lines
                    copyContext.draw(line)
                } else if shouldShowMoreIndicator {
                    drawLinesWithBlurEffect(index: index, layout: layout, in: &copyContext)
                } else {
                    // No "...more" indicator - just draw with fade based on progress
                    copyContext.opacity = progress
                    copyContext.draw(line)
                }
            }
        }
    }

    private func drawLinesWithBlurEffect(index: Int, layout: Text.Layout, in ctx: inout GraphicsContext) {
        let line = layout[index]

        let lineIndex = Double(index - length)
        let totalExtraLines = Double(layout.count - length)

        // Divide the animation progress among all extra lines
        let lineStartProgress = lineIndex / max(1, totalExtraLines)
        let lineEndProgress = (lineIndex + 1) / max(1, totalExtraLines)

        // Calculate this specific line's progress
        let lineProgress = max(0, min(1, (progress - lineStartProgress) / (lineEndProgress - lineStartProgress)))

        ctx.opacity = lineProgress
        ctx.addFilter(.blur(radius: blurRadius - (blurRadius * lineProgress)))
        ctx.draw(line)
    }

    private func drawMoreTextAtEnd(line: Text.Layout.Element, context: inout GraphicsContext) {
        let runs = line.flatMap { $0 }
        let runsCount = runs.count
        let text = " ..." + String(localized: "common.more")
        let textCount = text.count

        // Draw runs until the text count
        for index in 0..<max(runsCount - textCount, 0) {
            let run = runs[index]
            context.draw(run)
        }

        // Draw remaining runs with opacity filter
        for index in max(runsCount - textCount, 0)..<runsCount {
            let run = runs[index]
            context.opacity = progress
            context.draw(run)
        }

        // Draw "...more" text
        let textRunIndex = max(runsCount - textCount, 0)
        var typography: Text.Layout.TypographicBounds
        if !runs.isEmpty {
            typography = runs[textRunIndex].typographicBounds
        } else {
            typography = line.typographicBounds
        }

        let fontSize: CGFloat = typography.ascent
        let font = platformFont(ofSize: fontSize)

        let spacing: CGFloat = textWidth(text, font: font) / 2

        let swiftUIText = Text(text)
            .font(Font(font))
            .foregroundStyle(.secondary)

        let origin = CGPoint(
            x: typography.rect.minX + spacing,
            y: typography.rect.midY
        )

        context.opacity = 1 - progress
        context.draw(swiftUIText, at: origin)
    }

    private var blurRadius: CGFloat {
        5
    }

    // MARK: - Cross-Platform Font Helpers

    #if os(macOS)
    private func platformFont(ofSize size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size)
    }

    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (text as NSString).size(withAttributes: attributes).width
    }
    #else
    private func platformFont(ofSize size: CGFloat) -> UIFont {
        UIFont.systemFont(ofSize: size)
    }

    private func textWidth(_ text: String, font: UIFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (text as NSString).size(withAttributes: attributes).width
    }
    #endif
}
