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

    /// Whether a date is so close to now that a relative rendering of it reads
    /// "in 0 seconds".
    static func isEffectivelyNow(_ date: Date, tolerance: TimeInterval = 1) -> Bool {
        abs(Date().timeIntervalSince(date)) < tolerance
    }

    /// Whether a publication date is the stamp an instance writes when it has
    /// none to send.
    ///
    /// Invidious answers `published` with the moment it replied — and
    /// `publishedText` with "0 seconds ago" — for a video whose upload date it
    /// could not read, which renders as "in 0 seconds"; a scraping Piped does
    /// the same with `uploaded`. Read with a minute of slack, because the
    /// clocks at the two ends of a request are not the same clock, and because
    /// nothing reaches a listing within a minute of being published.
    static func isStampedNow(_ date: Date, tolerance: TimeInterval = 60) -> Bool {
        Date().timeIntervalSince(date) < tolerance
    }
}
