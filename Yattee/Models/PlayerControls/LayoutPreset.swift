//
//  LayoutPreset.swift
//  Yattee
//
//  A named preset containing a complete player controls layout.
//

import Foundation

/// A named preset containing a complete player controls layout.
struct LayoutPreset: Identifiable, Codable, Hashable, Sendable {
    /// Unique identifier for this preset.
    let id: UUID

    /// User-visible name for the preset. Maximum 30 characters.
    var name: String

    /// When this preset was created.
    let createdAt: Date

    /// When this preset was last modified.
    var updatedAt: Date

    /// Whether this is a built-in preset (read-only).
    let isBuiltIn: Bool

    /// The device class this preset is for.
    let deviceClass: DeviceClass

    /// The complete player controls layout.
    var layout: PlayerControlsLayout

    // MARK: - Constants

    /// Maximum length for preset names.
    static let maxNameLength = 30

    // MARK: - Initialization

    /// Creates a new layout preset.
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - name: Preset name. Truncated to 30 characters.
    ///   - createdAt: Creation date. Defaults to now.
    ///   - updatedAt: Last modified date. Defaults to now.
    ///   - isBuiltIn: Whether this is a built-in preset.
    ///   - deviceClass: Device class for this preset. Defaults to current.
    ///   - layout: The player controls layout.
    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isBuiltIn: Bool = false,
        deviceClass: DeviceClass = .current,
        layout: PlayerControlsLayout
    ) {
        self.id = id
        self.name = String(name.prefix(Self.maxNameLength))
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isBuiltIn = isBuiltIn
        self.deviceClass = deviceClass
        self.layout = layout
    }

    // MARK: - Mutation

    /// Creates a copy of this preset with updated layout and timestamp.
    /// - Parameter layout: The new layout.
    /// - Returns: A new preset with the updated layout.
    func withUpdatedLayout(_ layout: PlayerControlsLayout) -> LayoutPreset {
        var updated = self
        updated.layout = layout
        updated.updatedAt = Date()
        return updated
    }

    /// Creates a copy of this preset with a new name.
    /// - Parameter name: The new name.
    /// - Returns: A new preset with the updated name.
    func renamed(to name: String) -> LayoutPreset {
        var updated = self
        updated.name = String(name.prefix(Self.maxNameLength))
        updated.updatedAt = Date()
        return updated
    }

    /// Creates a duplicate of this preset as a custom (non-built-in) preset.
    /// - Parameter name: Name for the duplicate.
    /// - Returns: A new custom preset with the same layout.
    func duplicate(name: String) -> LayoutPreset {
        LayoutPreset(
            name: name,
            isBuiltIn: false,
            deviceClass: deviceClass,
            layout: layout
        )
    }
}

// MARK: - Equatable

extension LayoutPreset: Equatable {
    static func == (lhs: LayoutPreset, rhs: LayoutPreset) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.updatedAt == rhs.updatedAt
    }
}
