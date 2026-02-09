//
//  HomeShortcutCardView.swift
//  Yattee
//
//  Card component for home shortcuts.
//

import SwiftUI

struct HomeShortcutCardView<StatusIndicator: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    #endif

    let icon: String
    let title: String
    let count: Int
    let subtitle: String
    var statusIndicator: StatusIndicator?

    init(
        icon: String,
        title: String,
        count: Int,
        subtitle: String,
        statusIndicator: StatusIndicator?
    ) {
        self.icon = icon
        self.title = title
        self.count = count
        self.subtitle = subtitle
        self.statusIndicator = statusIndicator
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

    private var hasSubtitle: Bool {
        !subtitle.isEmpty
    }

    var body: some View {
        Group {
            if needsVerticalLayout {
                // Vertical layout for tvOS and accessibility sizes
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: iconSize)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(title)
                                .font(titleFont)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            if let statusIndicator {
                                statusIndicator.padding(.leading, 4)
                            }
                        }

                        if hasSubtitle {
                            Text(subtitle)
                                .font(subtitleFont)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: subtitleMinHeight, alignment: hasSubtitle ? .top : .center)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Horizontal layout for standard sizes
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: iconSize)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(title)
                                .font(titleFont)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .allowsTightening(true)
                                .lineLimit(1)
                            if let statusIndicator {
                                statusIndicator.padding(.leading, 4)
                            }
                        }

                        if hasSubtitle {
                            Text(subtitle)
                                .font(subtitleFont)
                                .foregroundStyle(.secondary)
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
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
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

    private var cardBackground: some ShapeStyle {
        #if os(tvOS)
        isFocused ? Color.white.opacity(0.2) : Color.gray.opacity(0.3)
        #else
        Color.accentColor.opacity(0.1)
        #endif
    }
}

// MARK: - Convenience Initializer (no status indicator)

extension HomeShortcutCardView where StatusIndicator == EmptyView {
    init(
        icon: String,
        title: String,
        count: Int,
        subtitle: String
    ) {
        self.icon = icon
        self.title = title
        self.count = count
        self.subtitle = subtitle
        self.statusIndicator = nil
    }
}
