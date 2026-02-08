//
//  RelativeDateFormatter.swift
//  Yattee
//
//  Centralized utility for formatting relative dates with "just now" support.
//

import Foundation

/// Utility for formatting dates relative to now, with proper handling of very recent times.
enum RelativeDateFormatter {
    /// Formats a date relative to now, showing "just now" for very recent dates.
    /// - Parameters:
    ///   - date: The date to format
    ///   - justNowThreshold: Seconds within which to show "just now" (default: 10)
    ///   - unitsStyle: The style for the relative date formatter (default: .abbreviated)
    /// - Returns: Formatted string (e.g., "just now", "5 min ago", "2 hours ago")
    static func string(
        for date: Date,
        justNowThreshold: TimeInterval = 10,
        unitsStyle: RelativeDateTimeFormatter.UnitsStyle = .abbreviated
    ) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < justNowThreshold {
            return String(localized: "common.justNow")
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = unitsStyle
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
