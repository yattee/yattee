//
//  TapGesturesSettings.swift
//  Yattee
//
//  Settings for tap gesture recognition and behavior.
//

import Foundation

/// Settings for tap gestures on the player.
struct TapGesturesSettings: Codable, Hashable, Sendable {
    /// Whether tap gestures are enabled.
    var isEnabled: Bool

    /// The zone layout to use.
    var layout: TapZoneLayout

    /// Configuration for each zone in the layout.
    var zoneConfigurations: [TapZoneConfiguration]

    /// Double-tap timing window in milliseconds.
    var doubleTapInterval: Int

    // MARK: - Initialization

    /// Creates tap gestures settings.
    /// - Parameters:
    ///   - isEnabled: Whether enabled (default: false).
    ///   - layout: Zone layout (default: horizontalSplit).
    ///   - zoneConfigurations: Zone configurations.
    ///   - doubleTapInterval: Double-tap timing in ms (default: 300).
    init(
        isEnabled: Bool = false,
        layout: TapZoneLayout = .horizontalSplit,
        zoneConfigurations: [TapZoneConfiguration]? = nil,
        doubleTapInterval: Int = 300
    ) {
        self.isEnabled = isEnabled
        self.layout = layout
        self.zoneConfigurations = zoneConfigurations ?? Self.defaultConfigurations(for: layout)
        self.doubleTapInterval = doubleTapInterval
    }

    // MARK: - Defaults

    /// Default settings with gestures disabled.
    static let `default` = TapGesturesSettings()

    /// Creates default zone configurations for a layout.
    /// - Parameter layout: The zone layout.
    /// - Returns: Default configurations with sensible actions.
    static func defaultConfigurations(for layout: TapZoneLayout) -> [TapZoneConfiguration] {
        layout.positions.map { position in
            TapZoneConfiguration(
                position: position,
                action: defaultAction(for: position)
            )
        }
    }

    /// Returns the default action for a zone position.
    private static func defaultAction(for position: TapZonePosition) -> TapGestureAction {
        switch position {
        case .full:
            .togglePlayPause
        case .left, .leftThird, .topLeft, .bottomLeft:
            .seekBackward(seconds: 10)
        case .right, .rightThird, .topRight, .bottomRight:
            .seekForward(seconds: 10)
        case .top:
            .togglePlayPause
        case .bottom:
            .togglePlayPause
        case .center:
            .togglePlayPause
        }
    }

    // MARK: - Helpers

    /// Returns the configuration for a specific position.
    /// - Parameter position: The zone position.
    /// - Returns: The configuration, or nil if not found.
    func configuration(for position: TapZonePosition) -> TapZoneConfiguration? {
        zoneConfigurations.first { $0.position == position }
    }

    /// Updates the configuration for a zone, or adds it if not present.
    /// - Parameter config: The updated configuration.
    /// - Returns: Updated settings.
    func withUpdatedConfiguration(_ config: TapZoneConfiguration) -> TapGesturesSettings {
        var settings = self
        if let index = settings.zoneConfigurations.firstIndex(where: { $0.position == config.position }) {
            settings.zoneConfigurations[index] = config
        } else {
            settings.zoneConfigurations.append(config)
        }
        return settings
    }

    /// Creates settings with a new layout, generating default configurations.
    /// - Parameter newLayout: The new layout.
    /// - Returns: Updated settings with new layout and configurations.
    func withLayout(_ newLayout: TapZoneLayout) -> TapGesturesSettings {
        var settings = self
        settings.layout = newLayout
        settings.zoneConfigurations = Self.defaultConfigurations(for: newLayout)
        return settings
    }

    // MARK: - Validation

    /// Double-tap interval range in milliseconds.
    static let doubleTapIntervalRange = 150...600
}
