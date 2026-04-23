//
//  CountFormatter.swift
//  Yattee
//
//  Centralized utility for formatting counts with compact notation (1K, 2.5K, etc.)
//

import Foundation

/// Utility for formatting counts with compact notation and proper pluralization.
enum CountFormatter {
    /// Formats a count to compact notation (e.g., 1K, 2.5K, 1M, 1B).
    /// - Parameter count: The number to format
    /// - Returns: Formatted string (e.g., "150", "1.2K", "2.5M", "1B")
    static func compact(_ count: Int) -> String {
        switch count {
        case 0..<1_000:
            return "\(count)"
        case 1_000..<1_000_000:
            let value = Double(count) / 1_000
            return String(format: "%.1fK", value).replacingOccurrences(of: ".0K", with: "K")
        case 1_000_000..<1_000_000_000:
            let value = Double(count) / 1_000_000
            return String(format: "%.1fM", value).replacingOccurrences(of: ".0M", with: "M")
        default:
            let value = Double(count) / 1_000_000_000
            return String(format: "%.1fB", value).replacingOccurrences(of: ".0B", with: "B")
        }
    }
}
