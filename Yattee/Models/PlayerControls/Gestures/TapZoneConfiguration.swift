//
//  TapZoneConfiguration.swift
//  Yattee
//
//  Configuration for a single tap zone's action.
//

import Foundation

/// Configuration for a tap zone, mapping a position to an action.
struct TapZoneConfiguration: Codable, Hashable, Sendable, Identifiable {
    /// Unique identifier for this configuration.
    var id: UUID

    /// The position of this zone within the layout.
    var position: TapZonePosition

    /// The action to perform when this zone is double-tapped.
    var action: TapGestureAction

    /// Creates a new tap zone configuration.
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID).
    ///   - position: Zone position.
    ///   - action: Action to perform.
    init(
        id: UUID = UUID(),
        position: TapZonePosition,
        action: TapGestureAction
    ) {
        self.id = id
        self.position = position
        self.action = action
    }

    /// Creates a configuration with a new action, preserving the ID.
    /// - Parameter newAction: The new action.
    /// - Returns: Updated configuration.
    func withAction(_ newAction: TapGestureAction) -> TapZoneConfiguration {
        TapZoneConfiguration(id: id, position: position, action: newAction)
    }
}
