//
//  SeekGestureSettings.swift
//  Yattee
//
//  Settings for horizontal seek gesture.
//

import Foundation

/// Settings for the horizontal drag-to-seek gesture on the player.
struct SeekGestureSettings: Codable, Hashable, Sendable {
    /// Whether the seek gesture is enabled.
    var isEnabled: Bool

    /// Sensitivity level controlling seek speed.
    var sensitivity: SeekGestureSensitivity

    // MARK: - Initialization

    /// Creates seek gesture settings.
    /// - Parameters:
    ///   - isEnabled: Whether enabled (default: false).
    ///   - sensitivity: Sensitivity level (default: medium).
    init(
        isEnabled: Bool = false,
        sensitivity: SeekGestureSensitivity = .medium
    ) {
        self.isEnabled = isEnabled
        self.sensitivity = sensitivity
    }

    // MARK: - Defaults

    /// Default settings with gesture disabled.
    static let `default` = SeekGestureSettings()
}
