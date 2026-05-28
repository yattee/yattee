//
//  HomeShortcutCardView.swift
//  Yattee
//
//  Card component for home shortcuts.
//

import SwiftUI

struct HomeShortcutCardView<StatusIndicator: View>: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Position-resolved colorful color; when set it overrides `colorfulColor`.
    @Environment(\.homeShortcutColorfulColor) private var positionColorfulColor
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    #endif

    private var accentColor: Color {
        appEnvironment?.settingsManager.accentColor.color ?? .accentColor
    }

    let icon: String
    let title: String
    let count: Int
    let subtitle: String
    /// Whether to show the count number in the filled (Reminders) layout.
    /// Cards without a meaningful count (Open Link, Remote, Subscriptions) hide it.
    var showsCount: Bool
    /// Fixed color used when the "colorful" card style is active.
    var colorfulColor: Color
    /// Explicit style override. When set, takes precedence over the global
    /// setting — used to render live previews of a not-yet-saved style.
    var styleOverride: HomeShortcutCardStyle?
    var statusIndicator: StatusIndicator?

    init(
        icon: String,
        title: String,
        count: Int,
        subtitle: String,
        showsCount: Bool = true,
        colorfulColor: Color = .accentColor,
        styleOverride: HomeShortcutCardStyle? = nil,
        statusIndicator: StatusIndicator?
    ) {
        self.icon = icon
        self.title = title
        self.count = count
        self.subtitle = subtitle
        self.showsCount = showsCount
        self.colorfulColor = colorfulColor
        self.styleOverride = styleOverride
        self.statusIndicator = statusIndicator
    }

    // MARK: - Card Style

    private var cardStyle: HomeShortcutCardStyle {
        #if os(tvOS)
        return .plain
        #else
        return styleOverride ?? (appEnvironment?.settingsManager.homeShortcutCardStyle ?? .plain)
        #endif
    }

    private var isFilled: Bool {
        cardStyle != .plain
    }

    private var fillColor: Color {
        cardStyle == .colorful ? (positionColorfulColor ?? colorfulColor) : accentColor
    }

    private var iconColor: Color {
        isFilled ? .white : accentColor
    }

    private var titleColor: Color {
        isFilled ? .white : .primary
    }

    private var subtitleColor: Color {
        isFilled ? Color.white.opacity(0.85) : .secondary
    }

    // Platform-specific styling
    #if os(tvOS)
    private let iconSize: CGFloat = 36
    private let titleFont: Font = .headline
    private let subtitleFont: Font = .subheadline.monospacedDigit()
    private let hPadding: CGFloat = 20
    private let vPadding: CGFloat = 20
    private let cornerRadius: CGFloat = 20
    #elseif os(macOS)
    private let iconSize: CGFloat = 28
    private let titleFont: Font = .body
    private let subtitleFont: Font = .subheadline.monospacedDigit()
    private let hPadding: CGFloat = 12
    private let vPadding: CGFloat = 12
    private let cornerRadius: CGFloat = 16
    #else
    private let iconSize: CGFloat = 28
    private let titleFont: Font = .subheadline
    private let subtitleFont: Font = .caption.monospacedDigit()
    private let hPadding: CGFloat = 12
    private let vPadding: CGFloat = 12
    private let cornerRadius: CGFloat = 16
    #endif

    private var needsVerticalLayout: Bool {
        #if os(tvOS)
        return true  // Always vertical on tvOS for better readability
        #else
        return dynamicTypeSize >= .xxxLarge
        #endif
    }

    /// Filled styles (accent/colorful) use a Reminders-style layout:
    /// icon top-leading, count top-trailing, title at the bottom.
    private var useRemindersLayout: Bool {
        #if os(tvOS)
        return false
        #else
        return isFilled
        #endif
    }

    private var hasSubtitle: Bool {
        !subtitle.isEmpty
    }

    var body: some View {
        Group {
            if useRemindersLayout {
                remindersLayout
            } else if needsVerticalLayout {
                // Vertical layout for tvOS and accessibility sizes
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(iconColor)
                        .frame(width: iconSize)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(title)
                                .font(titleFont)
                                .fontWeight(.semibold)
                                .foregroundStyle(titleColor)
                            if let statusIndicator {
                                statusIndicator.padding(.leading, 4)
                            }
                        }

                        Text(hasSubtitle ? subtitle : " ")
                            .font(subtitleFont)
                            .foregroundStyle(subtitleColor)
                            .opacity(hasSubtitle ? 1 : 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Horizontal layout for standard sizes
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(iconColor)
                        .frame(width: iconSize)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(title)
                                .font(titleFont)
                                .fontWeight(.semibold)
                                .foregroundStyle(titleColor)
                                .allowsTightening(true)
                                .lineLimit(1)
                            if let statusIndicator {
                                statusIndicator.padding(.leading, 4)
                            }
                        }

                        if hasSubtitle {
                            Text(subtitle)
                                .font(subtitleFont)
                                .foregroundStyle(subtitleColor)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(minHeight: subtitleMinHeight)
            }
        }
        .padding(.horizontal, hPadding)
        .padding(.vertical, vPadding)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// Reminders-style layout used by the accent/colorful filled styles:
    /// icon top-leading, count top-trailing, title anchored to the bottom.
    private var remindersLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(iconColor)

                Spacer(minLength: 4)

                if let statusIndicator {
                    statusIndicator
                }

                if showsCount {
                    Text(count, format: .number)
                        .font(.title2)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(title)
                .font(titleFont)
                .fontWeight(.semibold)
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, minHeight: remindersMinHeight, alignment: .leading)
    }

    /// Minimum height for the text content area to ensure consistent card heights
    private var subtitleMinHeight: CGFloat {
        #if os(tvOS)
        // headline + subheadline + spacing
        44
        #elseif os(macOS)
        // body + subheadline + spacing
        38
        #else
        // subheadline + caption + spacing
        34
        #endif
    }

    /// Minimum content height for the Reminders-style layout so the title sits
    /// well below the icon/count row (matches Apple's roomier card proportions).
    private var remindersMinHeight: CGFloat {
        #if os(macOS)
        64
        #else
        60
        #endif
    }

    @ViewBuilder
    private var cardBackground: some View {
        #if os(tvOS)
        (isFocused ? Color.white.opacity(0.2) : Color.gray.opacity(0.3))
        #else
        if isFilled {
            // Solid fill plus a subtle top-to-bottom sheen for a gentle gradient.
            fillColor.overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0.28), Color.clear, Color.black.opacity(0.10)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        } else {
            accentColor.opacity(0.1)
        }
        #endif
    }

    private var borderColor: Color {
        #if os(tvOS)
        return accentColor.opacity(0.3)
        #else
        return isFilled ? .clear : accentColor.opacity(0.3)
        #endif
    }
}

// MARK: - Convenience Initializer (no status indicator)

extension HomeShortcutCardView where StatusIndicator == EmptyView {
    init(
        icon: String,
        title: String,
        count: Int,
        subtitle: String,
        showsCount: Bool = true,
        colorfulColor: Color = .accentColor,
        styleOverride: HomeShortcutCardStyle? = nil
    ) {
        self.icon = icon
        self.title = title
        self.count = count
        self.subtitle = subtitle
        self.showsCount = showsCount
        self.colorfulColor = colorfulColor
        self.styleOverride = styleOverride
        self.statusIndicator = nil
    }
}
