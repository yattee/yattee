//
//  ButtonSettings.swift
//  Yattee
//
//  Settings types for configurable control buttons.
//

import Foundation

// MARK: - Spacer Settings

/// Configuration for spacer elements in the control layout.
struct SpacerSettings: Codable, Hashable, Sendable {
    /// Whether the spacer is flexible (expands to fill available space).
    var isFlexible: Bool

    /// Fixed width in points when not flexible. Range: 4-100, step: 2.
    var fixedWidth: Int

    /// Default spacer settings (flexible).
    init(isFlexible: Bool = true, fixedWidth: Int = 20) {
        self.isFlexible = isFlexible
        self.fixedWidth = Self.clampWidth(fixedWidth)
    }

    /// Clamps width to valid range (4-100) with 2pt step.
    static func clampWidth(_ width: Int) -> Int {
        let clamped = max(4, min(100, width))
        return (clamped / 2) * 2
    }
}

// MARK: - Slider Behavior

/// How a slider control (brightness/volume) behaves.
enum SliderBehavior: String, Codable, Hashable, Sendable, CaseIterable {
    /// Button and slider are always visible together.
    case alwaysVisible

    /// Only button is visible; slider expands on tap.
    case expandOnTap

    /// Slider visible in landscape, expand on tap in portrait.
    case autoExpandInLandscape

    /// Localized display name.
    var displayName: String {
        switch self {
        case .alwaysVisible:
            return String(localized: "controls.slider.alwaysVisible")
        case .expandOnTap:
            return String(localized: "controls.slider.expandOnTap")
        case .autoExpandInLandscape:
            return String(localized: "controls.slider.autoExpandInLandscape")
        }
    }
}

/// Configuration for slider buttons (brightness, volume).
struct SliderSettings: Codable, Hashable, Sendable {
    /// How the slider behaves.
    var sliderBehavior: SliderBehavior

    /// Default slider settings (expand on tap).
    init(sliderBehavior: SliderBehavior = .expandOnTap) {
        self.sliderBehavior = sliderBehavior
    }
}

// MARK: - Seek Direction

/// Direction for seek buttons in horizontal sections.
enum SeekDirection: String, Codable, Hashable, Sendable, CaseIterable {
    case backward
    case forward

    /// Localized display name.
    var displayName: String {
        switch self {
        case .backward:
            return String(localized: "controls.seek.backward")
        case .forward:
            return String(localized: "controls.seek.forward")
        }
    }
}

// MARK: - Seek Settings

/// Configuration for seek buttons (backward/forward).
struct SeekSettings: Codable, Hashable, Sendable {
    /// Number of seconds to seek. Default: 10.
    var seconds: Int

    /// Direction for horizontal section seek buttons. Default: .forward.
    var direction: SeekDirection

    /// Seek seconds that have dedicated SF Symbol icons.
    private static let validSeekIconValues = [5, 10, 15, 30, 45, 60, 75, 90]

    /// SF Symbol name for this seek button based on configured seconds and direction.
    /// Uses numbered icon for standard values (5, 10, 15, 30, 45, 60, 75, 90),
    /// plain arrow for other values.
    var systemImage: String {
        let arrowDirection = direction == .backward ? "counterclockwise" : "clockwise"
        if Self.validSeekIconValues.contains(seconds) {
            return "\(seconds).arrow.trianglehead.\(arrowDirection)"
        }
        return "arrow.trianglehead.\(arrowDirection)"
    }

    /// Default seek settings (10 seconds, forward direction).
    init(seconds: Int = 10, direction: SeekDirection = .forward) {
        self.seconds = max(1, seconds)
        self.direction = direction
    }

    // MARK: - Codable (backward compatibility)

    private enum CodingKeys: String, CodingKey {
        case seconds
        case direction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seconds = try container.decode(Int.self, forKey: .seconds)
        // Default to .forward for backward compatibility with existing configs
        direction = try container.decodeIfPresent(SeekDirection.self, forKey: .direction) ?? .forward
    }
}

// MARK: - Title/Author Settings

/// Configuration for the title/author button.
struct TitleAuthorSettings: Codable, Hashable, Sendable {
    /// Whether to show the source/author image.
    var showSourceImage: Bool

    /// Whether to show the video title.
    var showTitle: Bool

    /// Whether to show the source/author name.
    var showSourceName: Bool

    /// Default settings (all visible).
    init(showSourceImage: Bool = true, showTitle: Bool = true, showSourceName: Bool = true) {
        self.showSourceImage = showSourceImage
        self.showTitle = showTitle
        self.showSourceName = showSourceName
    }
}

// MARK: - Time Display Format

/// How the time display shows current/total time.
enum TimeDisplayFormat: String, Codable, Hashable, Sendable, CaseIterable {
    /// Shows only current time (e.g., "5:32").
    case currentOnly

    /// Shows current and total time (e.g., "5:32 / 12:45").
    case currentAndTotal

    /// Shows current and total, excluding SponsorBlock segments (e.g., "5:32 / 11:20").
    case currentAndTotalExcludingSponsor

    /// Shows current and remaining time (e.g., "5:32 / -7:13").
    case currentAndRemaining

    /// Shows current and remaining, excluding SponsorBlock segments.
    case currentAndRemainingExcludingSponsor

    /// Localized display name.
    var displayName: String {
        switch self {
        case .currentOnly:
            return String(localized: "controls.time.currentOnly")
        case .currentAndTotal:
            return String(localized: "controls.time.currentAndTotal")
        case .currentAndTotalExcludingSponsor:
            return String(localized: "controls.time.currentAndTotalExcludingSponsor")
        case .currentAndRemaining:
            return String(localized: "controls.time.currentAndRemaining")
        case .currentAndRemainingExcludingSponsor:
            return String(localized: "controls.time.currentAndRemainingExcludingSponsor")
        }
    }
}

/// Configuration for time display.
struct TimeDisplaySettings: Codable, Hashable, Sendable {
    /// Format for displaying time.
    var format: TimeDisplayFormat

    /// Default time display settings.
    init(format: TimeDisplayFormat = .currentAndTotal) {
        self.format = format
    }
}

// MARK: - Button Settings

/// Settings for a configurable control button.
/// Uses associated values for type-specific settings.
enum ButtonSettings: Codable, Hashable, Sendable {
    case spacer(SpacerSettings)
    case slider(SliderSettings)
    case seek(SeekSettings)
    case timeDisplay(TimeDisplaySettings)
    case titleAuthor(TitleAuthorSettings)

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case spacer
        case slider
        case seek
        case timeDisplay
        case titleAuthor
    }

    private enum SettingsType: String, Codable {
        case spacer
        case slider
        case seek
        case timeDisplay
        case titleAuthor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SettingsType.self, forKey: .type)

        switch type {
        case .spacer:
            let settings = try container.decode(SpacerSettings.self, forKey: .spacer)
            self = .spacer(settings)
        case .slider:
            let settings = try container.decode(SliderSettings.self, forKey: .slider)
            self = .slider(settings)
        case .seek:
            let settings = try container.decode(SeekSettings.self, forKey: .seek)
            self = .seek(settings)
        case .timeDisplay:
            let settings = try container.decode(TimeDisplaySettings.self, forKey: .timeDisplay)
            self = .timeDisplay(settings)
        case .titleAuthor:
            let settings = try container.decode(TitleAuthorSettings.self, forKey: .titleAuthor)
            self = .titleAuthor(settings)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .spacer(let settings):
            try container.encode(SettingsType.spacer, forKey: .type)
            try container.encode(settings, forKey: .spacer)
        case .slider(let settings):
            try container.encode(SettingsType.slider, forKey: .type)
            try container.encode(settings, forKey: .slider)
        case .seek(let settings):
            try container.encode(SettingsType.seek, forKey: .type)
            try container.encode(settings, forKey: .seek)
        case .timeDisplay(let settings):
            try container.encode(SettingsType.timeDisplay, forKey: .type)
            try container.encode(settings, forKey: .timeDisplay)
        case .titleAuthor(let settings):
            try container.encode(SettingsType.titleAuthor, forKey: .type)
            try container.encode(settings, forKey: .titleAuthor)
        }
    }
}
