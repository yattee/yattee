//
//  MarqueeText.swift
//  Yattee
//
//  Scrolling text for long content that doesn't fit in container.
//

import SwiftUI

struct MarqueeText: View {
    let text: String
    var font: Font = .subheadline
    var fontWeight: Font.Weight = .medium
    var foregroundStyle: Color = .primary
    var velocity: CGFloat = 30
    var spacing: CGFloat = 50
    var delayBeforeScrolling: Double = 3.0

    // MARK: - State

    @State private var containerWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var startTime: Date?

    // MARK: - Computed Properties

    private var needsScrolling: Bool {
        textWidth > containerWidth && containerWidth > 0
    }

    private var totalScrollDistance: CGFloat {
        textWidth + spacing
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            Group {
                if needsScrolling {
                    scrollingContent
                } else {
                    staticContent
                }
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                containerWidth = newWidth
                startTime = .now
            }
            .onAppear {
                containerWidth = geometry.size.width
            }
        }
        .frame(height: textHeight)
        .clipped()
        .onChange(of: text) {
            startTime = .now
        }
    }

    // MARK: - Static Content

    private var staticContent: some View {
        textView
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Scrolling Content

    private var scrollingContent: some View {
        TimelineView(.animation) { context in
            HStack(spacing: spacing) {
                textView
                textView
            }
            .offset(x: calculateOffset(at: context.date))
            .onAppear {
                if startTime == nil {
                    startTime = context.date
                }
            }
        }
    }

    // MARK: - Text View

    private var textView: some View {
        Text(text)
            .font(font.weight(fontWeight))
            .foregroundStyle(foregroundStyle)
            .lineLimit(1)
            .fixedSize()
            .measureWidth { width in
                if textWidth != width {
                    textWidth = width
                }
            }
    }

    // MARK: - Text Height

    private var textHeight: CGFloat {
        #if os(macOS)
        let nsFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return nsFont.boundingRectForFont.height
        #else
        let uiFont = UIFont.preferredFont(forTextStyle: .subheadline)
        return uiFont.lineHeight
        #endif
    }

    // MARK: - Offset Calculation

    private func calculateOffset(at date: Date) -> CGFloat {
        guard let startTime else { return 0 }

        let elapsed = date.timeIntervalSince(startTime)

        // During initial delay period, stay at start position
        guard elapsed >= delayBeforeScrolling else { return 0 }

        // Calculate cycle timing
        let scrollDuration = totalScrollDistance / velocity
        let cycleDuration = scrollDuration + delayBeforeScrolling

        // Determine position within current cycle
        let scrollElapsed = elapsed - delayBeforeScrolling
        let cyclePosition = scrollElapsed.truncatingRemainder(dividingBy: cycleDuration)

        // Pause phase - stay at start position
        if cyclePosition >= scrollDuration {
            return 0
        }

        // Scroll phase
        return -(cyclePosition * velocity)
    }
}

// MARK: - Width Measurement Extension

private extension View {
    func measureWidth(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        onChange(proxy.size.width)
                    }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        onChange(newWidth)
                    }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        Text("Short text (no scroll):")
            .font(.caption)
            .foregroundStyle(.secondary)
        MarqueeText(text: "Short text")
            .frame(width: 200)
            .border(Color.gray)

        Text("Long text (scrolls after 3s):")
            .font(.caption)
            .foregroundStyle(.secondary)
        MarqueeText(text: "This is a very long text that will scroll horizontally in a marquee style animation")
            .frame(width: 200)
            .border(Color.gray)

        Text("Custom styled (faster velocity):")
            .font(.caption)
            .foregroundStyle(.secondary)
        MarqueeText(
            text: "Custom styled marquee text with different settings and faster scroll speed",
            font: .caption,
            foregroundStyle: .secondary,
            velocity: 50
        )
        .frame(width: 150)
        .border(Color.gray)

        Text("Shorter delay (1s):")
            .font(.caption)
            .foregroundStyle(.secondary)
        MarqueeText(
            text: "This text starts scrolling after just one second delay",
            delayBeforeScrolling: 1.0
        )
        .frame(width: 200)
        .border(Color.gray)
    }
    .padding()
}
