//
//  ControlButtonConfiguration.swift
//  Yattee
//
//  Configuration for a single control button in the player layout.
//

import Foundation

/// Configuration for a single control button, including its type, visibility, and settings.
struct ControlButtonConfiguration: Identifiable, Codable, Hashable, Sendable {
    /// Unique identifier for this button configuration.
    let id: UUID

    /// The type of control button.
    let buttonType: ControlButtonType

    /// When this button should be visible based on orientation.
    var visibilityMode: VisibilityMode

    /// Type-specific settings for this button (if applicable).
    var settings: ButtonSettings?

    // MARK: - Initialization

    /// Creates a new button configuration.
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - buttonType: The type of control button.
    ///   - visibilityMode: When to show the button. Defaults to `.both`.
    ///   - settings: Type-specific settings. Defaults to the button type's default settings.
    init(
        id: UUID = UUID(),
        buttonType: ControlButtonType,
        visibilityMode: VisibilityMode = .both,
        settings: ButtonSettings? = nil
    ) {
        self.id = id
        self.buttonType = buttonType
        self.visibilityMode = visibilityMode
        self.settings = settings ?? buttonType.defaultSettings
    }

    // MARK: - Factory Methods

    /// Creates a default configuration for the given button type.
    /// - Parameter type: The button type.
    /// - Returns: A new configuration with default settings.
    static func defaultConfiguration(for type: ControlButtonType) -> ControlButtonConfiguration {
        ControlButtonConfiguration(buttonType: type)
    }

    /// Creates a configuration for a flexible spacer.
    /// - Returns: A spacer configuration with flexible width.
    static func flexibleSpacer() -> ControlButtonConfiguration {
        ControlButtonConfiguration(
            buttonType: .spacer,
            settings: .spacer(SpacerSettings(isFlexible: true))
        )
    }

    /// Creates a configuration for a fixed-width spacer.
    /// - Parameter width: The fixed width in points.
    /// - Returns: A spacer configuration with fixed width.
    static func fixedSpacer(width: Int) -> ControlButtonConfiguration {
        ControlButtonConfiguration(
            buttonType: .spacer,
            settings: .spacer(SpacerSettings(isFlexible: false, fixedWidth: width))
        )
    }

    // MARK: - Convenience Accessors

    /// Returns the spacer settings if this is a spacer button.
    var spacerSettings: SpacerSettings? {
        guard case .spacer(let settings) = settings else { return nil }
        return settings
    }

    /// Returns the slider settings if this is a slider button.
    var sliderSettings: SliderSettings? {
        guard case .slider(let settings) = settings else { return nil }
        return settings
    }

    /// Returns the seek settings if this is a seek button.
    var seekSettings: SeekSettings? {
        guard case .seek(let settings) = settings else { return nil }
        return settings
    }

    /// Returns the time display settings if this is a time display.
    var timeDisplaySettings: TimeDisplaySettings? {
        guard case .timeDisplay(let settings) = settings else { return nil }
        return settings
    }

    /// Returns the title/author settings if this is a title/author button.
    var titleAuthorSettings: TitleAuthorSettings? {
        guard case .titleAuthor(let settings) = settings else { return nil }
        return settings
    }
}
