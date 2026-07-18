//
//  SeekGestureSensitivity.swift
//  Yattee
//
//  Sensitivity levels for horizontal seek gesture.
//

import Foundation

/// Sensitivity presets for the horizontal seek gesture.
/// Controls how much seeking occurs per screen width of drag.
enum SeekGestureSensitivity: String, Codable, CaseIterable, Hashable, Sendable {
    case low
    case medium
    case high

    // MARK: - Seek Configuration

    /// Base seconds of seeking per full screen width drag.
    /// This value is scaled by video duration using a multiplier.
    var baseSecondsPerScreenWidth: Double {
        switch self {
        case .low: 30
        case .medium: 60
        case .high: 120
        }
    }

    // MARK: - Display

    /// Localized display name for the sensitivity level.
    var displayName: String {
        switch self {
        case .low:
            String(localized: "gestures.seek.sensitivity.low", defaultValue: "Low")
        case .medium:
            String(localized: "gestures.seek.sensitivity.medium", defaultValue: "Medium")
        case .high:
            String(localized: "gestures.seek.sensitivity.high", defaultValue: "High")
        }
    }

    /// Localized description of what this sensitivity level is best for.
    var description: String {
        switch self {
        case .low:
            String(localized: "gestures.seek.sensitivity.low.description", defaultValue: "Precise control")
        case .medium:
            String(localized: "gestures.seek.sensitivity.medium.description", defaultValue: "Balanced")
        case .high:
            String(localized: "gestures.seek.sensitivity.high.description", defaultValue: "Fast navigation")
        }
    }
}
