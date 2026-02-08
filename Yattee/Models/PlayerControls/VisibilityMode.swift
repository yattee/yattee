//
//  VisibilityMode.swift
//  Yattee
//
//  Defines visibility modes for control buttons based on device orientation.
//

import Foundation

/// Controls when a button is visible based on device orientation.
enum VisibilityMode: String, Codable, Hashable, Sendable, CaseIterable {
    /// Button is visible in both portrait and landscape orientations.
    case both

    /// Button is only visible in portrait orientation.
    case portraitOnly

    /// Button is only visible in landscape/wide orientation.
    case wideOnly

    // MARK: - Display

    /// Localized display name for the visibility mode.
    var displayName: String {
        switch self {
        case .both:
            return String(localized: "controls.visibility.both")
        case .portraitOnly:
            return String(localized: "controls.visibility.portraitOnly")
        case .wideOnly:
            return String(localized: "controls.visibility.wideOnly")
        }
    }

    // MARK: - Visibility Check

    /// Returns whether the button should be visible for the given layout state.
    /// - Parameter isWideLayout: True if the current layout is wide/landscape.
    /// - Returns: True if the button should be visible.
    func isVisible(isWideLayout: Bool) -> Bool {
        switch self {
        case .both:
            return true
        case .portraitOnly:
            return !isWideLayout
        case .wideOnly:
            return isWideLayout
        }
    }
}
