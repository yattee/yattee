//
//  PanscanGestureSettings.swift
//  Yattee
//
//  Settings for pinch-to-panscan gesture.
//

import Foundation

/// Settings for the pinch-to-panscan gesture on the player.
struct PanscanGestureSettings: Codable, Hashable, Sendable {
    /// Whether the panscan gesture is enabled.
    var isEnabled: Bool

    /// Whether to snap to 0 (fit) or 1 (fill) when released.
    /// If false, the value stays exactly where released (free zoom).
    var snapToEnds: Bool

    // MARK: - Initialization

    /// Creates panscan gesture settings.
    /// - Parameters:
    ///   - isEnabled: Whether enabled (default: true).
    ///   - snapToEnds: Whether to snap to fit/fill (default: true).
    init(
        isEnabled: Bool = true,
        snapToEnds: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.snapToEnds = snapToEnds
    }

    // MARK: - Defaults

    /// Default settings with gesture enabled and snap mode on.
    static let `default` = PanscanGestureSettings()
}
