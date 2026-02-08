//
//  PlayerControlsPreviewView.swift
//  Yattee
//
//  Preview component showing player controls layout in settings.
//

import SwiftUI

// MARK: - Preview Theme Modifier

/// A view modifier that applies the controls theme color scheme to preview.
struct PreviewThemeModifier: ViewModifier {
    let theme: ControlsTheme
    @Environment(\.colorScheme) private var systemColorScheme

    func body(content: Content) -> some View {
        if let forcedScheme = theme.colorScheme {
            content.environment(\.colorScheme, forcedScheme)
        } else {
            // Default to dark for preview since it's on black background
            content.environment(\.colorScheme, .dark)
        }
    }
}

/// A static preview of the player controls layout for the settings view.
struct PlayerControlsPreviewView: View {
    let layout: PlayerControlsLayout
    let isLandscape: Bool

    var body: some View {
        GeometryReader { geometry in
            let containerWidth = geometry.size.width
            let containerHeight = geometry.size.height

            // Use 16:9 aspect ratio for both modes, capped at container height
            let aspectRatioHeight = containerWidth / (16.0 / 9.0)
            let previewWidth = containerWidth
            let previewHeight = min(containerHeight, aspectRatioHeight)

            previewContent(width: previewWidth, height: previewHeight)
                .position(x: containerWidth / 2, y: containerHeight / 2)
        }
    }

    // MARK: - Preview Content

    @ViewBuilder
    private func previewContent(width: CGFloat, height: CGFloat) -> some View {
        // Calculate minimum width needed for all buttons
        let minContentWidth = calculateMinimumContentWidth()
        let contentWidth = max(width, minContentWidth)
        let needsScrolling = contentWidth > width

        ScrollView(.horizontal, showsIndicators: needsScrolling) {
            previewContentView(width: contentWidth, height: height)
                .frame(width: contentWidth, height: height)
        }
        .scrollDisabled(!needsScrolling)
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .modifier(PreviewThemeModifier(theme: layout.globalSettings.theme))
    }

    /// Calculate minimum width needed to display all buttons without overlap
    private func calculateMinimumContentWidth() -> CGFloat {
        let topButtons = visibleButtons(in: layout.topSection)
        let bottomButtons = visibleButtons(in: layout.bottomSection)

        let topWidth = calculateSectionWidth(buttons: topButtons)
        let bottomWidth = calculateSectionWidth(buttons: bottomButtons)

        // Return the larger of top/bottom, plus padding
        return max(topWidth, bottomWidth) + (previewPadding * 2)
    }

    /// Whether buttons have glass backgrounds (affects frame sizes).
    private var hasButtonBackground: Bool {
        layout.globalSettings.buttonBackground.glassStyle != nil
    }

    /// Frame size for regular buttons - matches ControlsSectionRenderer
    private var regularButtonFrameSize: CGFloat {
        hasButtonBackground ? previewButtonBackgroundSize : previewButtonSize
    }

    /// Frame size for slider icons - matches ControlsSectionRenderer
    private var sliderIconFrameSize: CGFloat {
        hasButtonBackground ? previewButtonBackgroundSize : previewButtonSize
    }

    /// Calculate width needed for a section's buttons
    private func calculateSectionWidth(buttons: [ControlButtonConfiguration]) -> CGFloat {
        var totalWidth: CGFloat = 0
        var hasFlexibleSpacer = false
        let sliderWidth: CGFloat = 80 * previewScale // Matches actual player slider width

        for button in buttons {
            if button.buttonType == .spacer {
                if let settings = button.settings,
                   case .spacer(let spacerSettings) = settings {
                    if spacerSettings.isFlexible {
                        hasFlexibleSpacer = true
                        totalWidth += 20 // Minimum width for flexible spacer
                    } else {
                        totalWidth += CGFloat(spacerSettings.fixedWidth) * previewScale
                    }
                }
            } else if button.buttonType == .timeDisplay {
                totalWidth += 60 // Approximate width for time display text
            } else if button.buttonType == .brightness || button.buttonType == .volume {
                let behavior = button.sliderSettings?.sliderBehavior ?? .expandOnTap
                let effectiveBehavior: SliderBehavior = {
                    if behavior == .autoExpandInLandscape {
                        return isLandscape ? .alwaysVisible : .expandOnTap
                    }
                    return behavior
                }()
                if effectiveBehavior == .alwaysVisible {
                    // Slider icon + spacing + slider track
                    totalWidth += sliderIconFrameSize + 3 + sliderWidth
                } else {
                    totalWidth += sliderIconFrameSize
                }
            } else if button.buttonType == .titleAuthor {
                // Title/Author button is wider - estimate based on settings
                let settings = button.titleAuthorSettings ?? TitleAuthorSettings()
                var width: CGFloat = 0
                if settings.showSourceImage { width += previewButtonSize * 1.2 + 4 }
                if settings.showTitle || settings.showSourceName { width += 50 * previewScale }
                if hasButtonBackground { width += 12 } // padding
                totalWidth += max(width, regularButtonFrameSize)
            } else {
                totalWidth += regularButtonFrameSize
            }
            totalWidth += previewButtonSpacing
        }

        // If there's a flexible spacer, add extra minimum space
        if hasFlexibleSpacer {
            totalWidth += 40
        }

        return totalWidth
    }

    @ViewBuilder
    private func previewContentView(width: CGFloat, height: CGFloat) -> some View {
        // Video background
        Image("PlayerControlsPreviewBackground")
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipped()
            .overlay {
                // Solid color shade matching the controls opacity setting
                Color.black.opacity(layout.globalSettings.controlsFadeOpacity)
            }
            .overlay {
                // Controls overlay using ZStack for precise positioning
                ZStack {
                    // Top section - aligned to top trailing
                    VStack {
                        HStack(spacing: previewButtonSpacing) {
                            ForEach(visibleButtons(in: layout.topSection)) { button in
                                PreviewButton(
                                    configuration: button,
                                    size: previewButtonSize,
                                    backgroundSize: previewButtonBackgroundSize,
                                    isLandscape: isLandscape,
                                    fontStyle: layout.globalSettings.fontStyle,
                                    buttonBackground: layout.globalSettings.buttonBackground,
                                    previewScale: previewScale,
                                    buttonSize: layout.globalSettings.buttonSize
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, previewPadding)
                        .padding(.top, previewPadding)
                        Spacer()
                    }

                    // Center section
                    HStack(spacing: previewCenterSpacing) {
                        if layout.centerSettings.showSeekBackward {
                            PreviewCenterButton(
                                systemImage: layout.centerSettings.seekBackwardSystemImage,
                                fontSize: previewSeekFontSize,
                                frameSize: previewSeekButtonSize,
                                buttonBackground: layout.globalSettings.buttonBackground
                            )
                        }

                        if layout.centerSettings.showPlayPause {
                            PreviewCenterButton(
                                systemImage: "play.fill",
                                fontSize: previewPlayFontSize,
                                frameSize: previewPlayButtonSize,
                                buttonBackground: layout.globalSettings.buttonBackground
                            )
                        }

                        if layout.centerSettings.showSeekForward {
                            PreviewCenterButton(
                                systemImage: layout.centerSettings.seekForwardSystemImage,
                                fontSize: previewSeekFontSize,
                                frameSize: previewSeekButtonSize,
                                buttonBackground: layout.globalSettings.buttonBackground
                            )
                        }
                    }

                    // Bottom section - aligned to bottom leading
                    VStack {
                        Spacer()
                        HStack(spacing: previewButtonSpacing) {
                            ForEach(visibleButtons(in: layout.bottomSection)) { button in
                                PreviewButton(
                                    configuration: button,
                                    size: previewButtonSize,
                                    backgroundSize: previewButtonBackgroundSize,
                                    isLandscape: isLandscape,
                                    fontStyle: layout.globalSettings.fontStyle,
                                    buttonBackground: layout.globalSettings.buttonBackground,
                                    previewScale: previewScale,
                                    buttonSize: layout.globalSettings.buttonSize
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, previewPadding)
                        .padding(.bottom, previewPadding)
                    }
                }
            }
    }

    // MARK: - Layout Constants

    /// Scale factor for preview (to fit in settings view)
    private var previewScale: CGFloat { 0.55 }

    /// Button size for top/bottom bars - matches ControlsSectionRenderer which uses buttonSize.pointSize
    private var previewButtonSize: CGFloat {
        layout.globalSettings.buttonSize.pointSize * previewScale
    }

    /// Background size for buttons (slightly larger than button, matching ControlsSectionRenderer)
    private var previewButtonBackgroundSize: CGFloat {
        layout.globalSettings.buttonSize.pointSize * 1.15 * previewScale
    }

    /// Center button sizes - matches PlayerControlsView hardcoded values
    private var previewSeekButtonSize: CGFloat {
        let hasBackground = layout.globalSettings.buttonBackground.glassStyle != nil
        return (hasBackground ? 64 : 56) * previewScale
    }

    private var previewPlayButtonSize: CGFloat {
        let hasBackground = layout.globalSettings.buttonBackground.glassStyle != nil
        return (hasBackground ? 82 : 72) * previewScale
    }

    /// Font sizes for center buttons - matches PlayerControlsView hardcoded values
    private var previewSeekFontSize: CGFloat { 36 * previewScale }
    private var previewPlayFontSize: CGFloat { 56 * previewScale }

    private var previewButtonSpacing: CGFloat { 8 }

    private var previewCenterSpacing: CGFloat {
        let hasBackground = layout.globalSettings.buttonBackground.glassStyle != nil
        return (hasBackground ? 40 : 32) * previewScale
    }

    private var previewPadding: CGFloat { 12 }

    // MARK: - Helpers

    private func visibleButtons(in section: LayoutSection) -> [ControlButtonConfiguration] {
        section.visibleButtons(isWideLayout: isLandscape)
    }
}

// MARK: - Preview Button

private struct PreviewButton: View {
    let configuration: ControlButtonConfiguration
    /// Button frame size (for tap target)
    let size: CGFloat
    /// Background frame size (for glass background, slightly larger)
    let backgroundSize: CGFloat
    let isLandscape: Bool
    let fontStyle: ControlsFontStyle
    let buttonBackground: ButtonBackgroundStyle
    /// Scale factor for preview (used for slider width calculations)
    let previewScale: CGFloat
    /// Button size setting (small/medium/large) for icon scaling
    let buttonSize: ButtonSize

    /// Whether this button should show a glass background.
    private var hasBackground: Bool { buttonBackground.glassStyle != nil }

    /// Frame size - use backgroundSize when glass background enabled
    private var frameSize: CGFloat { hasBackground ? backgroundSize : size }

    /// Icon font size - uses buttonSize.iconSize to match actual player renderer
    private var iconFontSize: CGFloat { buttonSize.iconSize * previewScale }

    var body: some View {
        Group {
            if configuration.buttonType == .spacer {
                // Spacer
                if let settings = configuration.settings,
                   case .spacer(let spacerSettings) = settings,
                   spacerSettings.isFlexible {
                    Spacer()
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: spacerWidth)
                }
            } else if configuration.buttonType == .timeDisplay {
                // Time display
                Text("0:00 / 3:45")
                    .font(fontStyle.font(.caption))
                    .foregroundStyle(.white.opacity(0.9))
            } else if configuration.buttonType == .brightness || configuration.buttonType == .volume {
                // Slider buttons (brightness/volume) - show based on behavior
                sliderPreview
            } else if configuration.buttonType == .titleAuthor {
                // Title/Author button - show preview matching actual layout
                titleAuthorPreview
            } else {
                // Regular button
                regularButtonContent
            }
        }
        .opacity(buttonOpacity)
    }

    // MARK: - Regular Button Content

    @ViewBuilder
    private var regularButtonContent: some View {
        if let glassStyle = buttonBackground.glassStyle {
            Image(systemName: configuration.buttonType.systemImage)
                .font(.system(size: iconFontSize))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: frameSize, height: frameSize)
                .glassBackground(glassStyle, in: .circle, fallback: .ultraThinMaterial)
        } else {
            Image(systemName: configuration.buttonType.systemImage)
                .font(.system(size: iconFontSize))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: frameSize, height: frameSize)
        }
    }

    // MARK: - Title/Author Preview

    @ViewBuilder
    private var titleAuthorPreview: some View {
        let settings = configuration.titleAuthorSettings ?? TitleAuthorSettings()
        let avatarSize = size * 1.2

        HStack(spacing: 4) {
            // Avatar placeholder
            if settings.showSourceImage {
                Circle()
                    .fill(.white.opacity(0.3))
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay {
                        Text("Y")
                            .font(.system(size: size * 0.6, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
            }

            // Title and author stack
            if settings.showTitle || settings.showSourceName {
                VStack(alignment: .leading, spacing: 0) {
                    if settings.showTitle {
                        Text("Video Title")
                            .font(fontStyle.font(size: size * 0.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }

                    if settings.showSourceName {
                        Text("Channel")
                            .font(fontStyle.font(size: size * 0.4))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, buttonBackground.glassStyle != nil ? 6 : 0)
        .padding(.vertical, buttonBackground.glassStyle != nil ? 3 : 0)
        .modifier(OptionalCapsuleGlassBackgroundModifier(style: buttonBackground))
    }

    // MARK: - Slider Preview

    @ViewBuilder
    private var sliderPreview: some View {
        let behavior = configuration.sliderSettings?.sliderBehavior ?? .expandOnTap

        // Compute effective behavior based on orientation for autoExpandInLandscape
        let effectiveBehavior: SliderBehavior = {
            if behavior == .autoExpandInLandscape {
                return isLandscape ? .alwaysVisible : .expandOnTap
            }
            return behavior
        }()

        HStack(spacing: 3) {
            // Icon with optional glass background
            sliderIconContent

            // Fake slider - show when effectively always visible
            if effectiveBehavior == .alwaysVisible {
                ZStack(alignment: .leading) {
                    // Slider track - 80pt width in actual player, scaled for preview
                    let sliderWidth: CGFloat = 80 * previewScale
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white.opacity(0.3))
                        .frame(width: sliderWidth, height: 3)

                    // Slider fill (showing ~60% filled)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white.opacity(0.8))
                        .frame(width: sliderWidth * 0.6, height: 3)
                }
            }
        }
    }

    @ViewBuilder
    private var sliderIconContent: some View {
        if let glassStyle = buttonBackground.glassStyle {
            Image(systemName: configuration.buttonType.systemImage)
                .font(.system(size: iconFontSize))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: frameSize, height: frameSize)
                .glassBackground(glassStyle, in: .circle, fallback: .ultraThinMaterial)
        } else {
            Image(systemName: configuration.buttonType.systemImage)
                .font(.system(size: iconFontSize))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: frameSize, height: frameSize)
        }
    }

    private var spacerWidth: CGFloat {
        guard let settings = configuration.settings,
              case .spacer(let spacerSettings) = settings else {
            return 8
        }
        return CGFloat(spacerSettings.fixedWidth) * previewScale
    }

    private var buttonOpacity: Double {
        // Could dim buttons that don't match current orientation
        1.0
    }
}

// MARK: - Preview Center Button

private struct PreviewCenterButton: View {
    let systemImage: String
    let fontSize: CGFloat
    let frameSize: CGFloat
    let buttonBackground: ButtonBackgroundStyle

    /// Background frame size (slightly larger when background is enabled).
    private var backgroundFrameSize: CGFloat {
        buttonBackground.glassStyle != nil ? frameSize * 1.15 : frameSize
    }

    var body: some View {
        if let glassStyle = buttonBackground.glassStyle {
            Image(systemName: systemImage)
                .font(.system(size: fontSize))
                .foregroundStyle(.white)
                .frame(width: backgroundFrameSize, height: backgroundFrameSize)
                .glassBackground(glassStyle, in: .circle, fallback: .ultraThinMaterial)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: fontSize))
                .foregroundStyle(.white)
                .frame(width: frameSize, height: frameSize)
        }
    }
}

// MARK: - Optional Capsule Glass Background Modifier

/// A view modifier that conditionally applies a capsule glass background.
private struct OptionalCapsuleGlassBackgroundModifier: ViewModifier {
    let style: ButtonBackgroundStyle

    func body(content: Content) -> some View {
        if let glassStyle = style.glassStyle {
            content.glassBackground(glassStyle, in: .capsule, fallback: .ultraThinMaterial)
        } else {
            content
        }
    }
}

// MARK: - Preview

#Preview("Landscape") {
    PlayerControlsPreviewView(
        layout: .default,
        isLandscape: true
    )
    .frame(height: 200)
    .padding()
    .background(Color.gray.opacity(0.2))
}

#Preview("Portrait") {
    PlayerControlsPreviewView(
        layout: .default,
        isLandscape: false
    )
    .frame(height: 300)
    .padding()
    .background(Color.gray.opacity(0.2))
}
