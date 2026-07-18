//
//  GesturesSettings.swift
//  Yattee
//
//  Combined settings for all player gestures.
//

import Foundation

/// Combined settings for player gestures.
struct GesturesSettings: Codable, Hashable, Sendable {
    /// Settings for tap gestures.
    var tapGestures: TapGesturesSettings

    /// Settings for horizontal seek gesture.
    var seekGesture: SeekGestureSettings

    /// Settings for pinch-to-panscan gesture.
    var panscanGesture: PanscanGestureSettings

    // MARK: - Initialization

    /// Creates combined gestures settings.
    /// - Parameters:
    ///   - tapGestures: Tap gesture settings.
    ///   - seekGesture: Seek gesture settings.
    ///   - panscanGesture: Panscan gesture settings.
    init(
        tapGestures: TapGesturesSettings = .default,
        seekGesture: SeekGestureSettings = .default,
        panscanGesture: PanscanGestureSettings = .default
    ) {
        self.tapGestures = tapGestures
        self.seekGesture = seekGesture
        self.panscanGesture = panscanGesture
    }

    // MARK: - Defaults

    /// Default settings with all gestures disabled.
    static let `default` = GesturesSettings()

    // MARK: - Computed Properties

    /// Whether tap gestures are enabled.
    var areTapGesturesActive: Bool {
        tapGestures.isEnabled
    }

    /// Whether seek gesture is enabled.
    var isSeekGestureActive: Bool {
        seekGesture.isEnabled
    }

    /// Whether panscan gesture is enabled.
    var isPanscanGestureActive: Bool {
        panscanGesture.isEnabled
    }

    /// Whether any gestures are effectively enabled.
    var hasActiveGestures: Bool {
        areTapGesturesActive || isSeekGestureActive || isPanscanGestureActive
    }
}
