//
//  ListBackgroundStyle.swift
//  Yattee
//
//  Platform-specific background colors for list containers.
//

import SwiftUI

/// Background style variants for list containers.
///
/// Provides consistent platform-specific colors for grouped lists,
/// plain lists, and card backgrounds across iOS, macOS, and tvOS.
enum ListBackgroundStyle {
    /// Grouped background (systemGroupedBackground on iOS).
    /// Used as outer background for inset list style.
    case grouped

    /// Plain background (systemBackground on iOS).
    /// Used as outer background for plain list style.
    case plain

    /// Card/row background (secondarySystemGroupedBackground on iOS).
    /// Used for the card container in inset list style.
    case card

    /// Returns the platform-appropriate color for this background style.
    var color: Color {
        switch self {
        case .grouped:
            #if os(iOS)
            Color(uiColor: .systemGroupedBackground)
            #elseif os(macOS)
            Color(nsColor: .windowBackgroundColor)
            #else
            Color.black.opacity(0.9)
            #endif

        case .plain:
            #if os(iOS)
            Color(uiColor: .systemBackground)
            #elseif os(macOS)
            Color(nsColor: .windowBackgroundColor)
            #else
            Color.clear
            #endif

        case .card:
            #if os(iOS)
            Color(uiColor: .secondarySystemGroupedBackground)
            #elseif os(macOS)
            Color(nsColor: .controlBackgroundColor)
            #else
            Color.gray.opacity(0.2)
            #endif
        }
    }
}
