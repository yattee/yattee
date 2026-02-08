//
//  GlobalLayoutSettings.swift
//  Yattee
//
//  Global settings that apply to all control buttons in the player layout.
//

import Foundation
import SwiftUI

/// Theme options for player controls appearance.
enum ControlsTheme: String, Codable, Hashable, Sendable, CaseIterable {
    /// Follow system appearance
    case system

    /// Always use light appearance
    case light

    /// Always use dark appearance
    case dark

    /// Localized display name.
    var displayName: String {
        switch self {
        case .system:
            return String(localized: "controls.theme.system")
        case .light:
            return String(localized: "controls.theme.light")
        case .dark:
            return String(localized: "controls.theme.dark")
        }
    }

    /// Returns the ColorScheme to apply, or nil for system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

/// Size options for control buttons.
enum ButtonSize: String, Codable, Hashable, Sendable, CaseIterable {
    case small
    case medium
    case large

    /// The point size for buttons at this size.
    var pointSize: CGFloat {
        switch self {
        case .small:
            return 36
        case .medium:
            return 44
        case .large:
            return 52
        }
    }

    /// The icon size relative to button size.
    var iconSize: CGFloat {
        switch self {
        case .small:
            return 18
        case .medium:
            return 22
        case .large:
            return 26
        }
    }

    /// Localized display name.
    var displayName: String {
        switch self {
        case .small:
            return String(localized: "controls.size.small")
        case .medium:
            return String(localized: "controls.size.medium")
        case .large:
            return String(localized: "controls.size.large")
        }
    }
}

/// Background style options for control buttons.
enum ButtonBackgroundStyle: String, Codable, Hashable, Sendable, CaseIterable {
    /// No background (default, current behavior)
    case none

    /// Clear glass - subtle circular glass background
    case clearGlass

    /// Regular glass - more visible circular glass background
    case regularGlass

    /// Localized display name.
    var displayName: String {
        switch self {
        case .none:
            return String(localized: "controls.buttonBackground.none")
        case .clearGlass:
            return String(localized: "controls.buttonBackground.clearGlass")
        case .regularGlass:
            return String(localized: "controls.buttonBackground.regularGlass")
        }
    }

    /// The GlassStyle to use for this background style.
    var glassStyle: GlassStyle? {
        switch self {
        case .none:
            return nil
        case .clearGlass:
            return .clear
        case .regularGlass:
            return .regular
        }
    }
}

/// Overall style for player controls appearance.
enum ControlsStyle: String, Codable, Hashable, Sendable, CaseIterable {
    /// No background, follows system theme
    case plain

    /// Regular glass background, always dark theme
    case glass

    /// Localized display name.
    var displayName: String {
        switch self {
        case .plain:
            return String(localized: "controls.style.plain")
        case .glass:
            return String(localized: "controls.style.glass")
        }
    }

    /// The theme to apply for this style.
    var theme: ControlsTheme {
        switch self {
        case .plain:
            return .system
        case .glass:
            return .dark
        }
    }

    /// The button background to apply for this style.
    var buttonBackground: ButtonBackgroundStyle {
        switch self {
        case .plain:
            return .none
        case .glass:
            return .regularGlass
        }
    }
}

// MARK: - Codable Color

/// A color stored as RGBA components for Codable support.
struct CodableColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    /// Creates a CodableColor from RGBA components.
    /// - Parameters:
    ///   - red: Red component (0-1).
    ///   - green: Green component (0-1).
    ///   - blue: Blue component (0-1).
    ///   - opacity: Opacity component (0-1). Defaults to 1.
    init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    /// Creates a CodableColor from a SwiftUI Color.
    /// - Parameter color: The SwiftUI Color to convert.
    init(_ color: Color) {
        let resolved = color.resolve(in: EnvironmentValues())
        self.red = Double(resolved.red)
        self.green = Double(resolved.green)
        self.blue = Double(resolved.blue)
        self.opacity = Double(resolved.opacity)
    }

    /// Converts to a SwiftUI Color.
    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

// MARK: - SponsorBlock Segment Settings

/// Settings for a single SponsorBlock category's appearance on the progress bar.
struct SponsorBlockCategorySettings: Codable, Hashable, Sendable {
    /// Whether this category is visible on the progress bar.
    var isVisible: Bool

    /// The color to use for this category's segments.
    var color: CodableColor

    /// Creates category settings.
    /// - Parameters:
    ///   - isVisible: Whether the category is visible. Defaults to `true`.
    ///   - color: The color for segments. Defaults to gray.
    init(isVisible: Bool = true, color: CodableColor = CodableColor(red: 0.5, green: 0.5, blue: 0.5)) {
        self.isVisible = isVisible
        self.color = color
    }
}

/// Settings for SponsorBlock segment display on the progress bar.
struct SponsorBlockSegmentSettings: Codable, Hashable, Sendable {
    /// Global toggle for showing sponsor segments on the progress bar.
    var showSegments: Bool

    /// Per-category settings, keyed by SponsorBlockCategory raw value.
    var categorySettings: [String: SponsorBlockCategorySettings]

    /// Creates sponsor block segment settings.
    /// - Parameters:
    ///   - showSegments: Whether to show segments. Defaults to `true`.
    ///   - categorySettings: Per-category settings. Defaults to default colors for all categories.
    init(
        showSegments: Bool = true,
        categorySettings: [String: SponsorBlockCategorySettings]? = nil
    ) {
        self.showSegments = showSegments
        self.categorySettings = categorySettings ?? Self.defaultCategorySettings
    }

    /// Default settings with all categories visible using their default overlay colors.
    static let `default` = SponsorBlockSegmentSettings()

    /// Default category settings using default colors for each category.
    /// Colors match the SponsorBlockCategory.overlayColor values.
    static var defaultCategorySettings: [String: SponsorBlockCategorySettings] {
        [
            "sponsor": SponsorBlockCategorySettings(isVisible: true, color: CodableColor(.green)),
            "selfpromo": SponsorBlockCategorySettings(isVisible: true, color: CodableColor(.yellow)),
            "interaction": SponsorBlockCategorySettings(isVisible: true, color: CodableColor(.purple)),
            "intro": SponsorBlockCategorySettings(isVisible: true, color: CodableColor(.cyan)),
            "outro": SponsorBlockCategorySettings(isVisible: true, color: CodableColor(.blue)),
            "preview": SponsorBlockCategorySettings(isVisible: true, color: CodableColor(.indigo)),
            "music_offtopic": SponsorBlockCategorySettings(isVisible: true, color: CodableColor(.orange)),
            "filler": SponsorBlockCategorySettings(isVisible: true, color: CodableColor(.gray)),
            "poi_highlight": SponsorBlockCategorySettings(isVisible: true, color: CodableColor(.pink)),
        ]
    }

    /// Gets settings for a specific category key, returning defaults if not found.
    /// - Parameter categoryKey: The category raw value key.
    /// - Returns: The category settings.
    func settings(forKey categoryKey: String) -> SponsorBlockCategorySettings {
        categorySettings[categoryKey] ?? Self.defaultCategorySettings[categoryKey]
            ?? SponsorBlockCategorySettings()
    }

    /// Returns a copy with updated settings for a specific category key.
    /// - Parameters:
    ///   - categoryKey: The category raw value key.
    ///   - settings: The new settings.
    /// - Returns: Updated SponsorBlockSegmentSettings.
    func withUpdatedSettings(
        forKey categoryKey: String,
        _ settings: SponsorBlockCategorySettings
    ) -> SponsorBlockSegmentSettings {
        var newCategorySettings = categorySettings
        newCategorySettings[categoryKey] = settings
        return SponsorBlockSegmentSettings(
            showSegments: showSegments,
            categorySettings: newCategorySettings
        )
    }
}

// MARK: - SponsorBlockCategory Integration

extension SponsorBlockSegmentSettings {
    /// Gets settings for a specific category, returning defaults if not found.
    /// - Parameter category: The category to get settings for.
    /// - Returns: The category settings.
    func settings(for category: SponsorBlockCategory) -> SponsorBlockCategorySettings {
        settings(forKey: category.rawValue)
    }

    /// Returns a copy with updated settings for a specific category.
    /// - Parameters:
    ///   - category: The category to update.
    ///   - settings: The new settings.
    /// - Returns: Updated SponsorBlockSegmentSettings.
    func withUpdatedSettings(
        for category: SponsorBlockCategory,
        _ settings: SponsorBlockCategorySettings
    ) -> SponsorBlockSegmentSettings {
        withUpdatedSettings(forKey: category.rawValue, settings)
    }
}

// MARK: - Font Style

/// Font style options for player controls text.
enum ControlsFontStyle: String, Codable, Hashable, Sendable, CaseIterable {
    /// System default font with monospaced digits.
    case system

    /// Fully monospaced font.
    case monospaced

    /// Rounded system font with monospaced digits.
    case rounded

    /// Localized display name.
    var displayName: String {
        switch self {
        case .system:
            return String(localized: "controls.fontStyle.system")
        case .monospaced:
            return String(localized: "controls.fontStyle.monospaced")
        case .rounded:
            return String(localized: "controls.fontStyle.rounded")
        }
    }

    /// Returns a Font for the given text style.
    func font(_ style: Font.TextStyle = .caption) -> Font {
        switch self {
        case .system:
            return .system(style).monospacedDigit()
        case .monospaced:
            return .system(style, design: .monospaced)
        case .rounded:
            return .system(style, design: .rounded).monospacedDigit()
        }
    }

    /// Returns a Font for the given size and weight.
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .system:
            return .system(size: size, weight: weight).monospacedDigit()
        case .monospaced:
            return .system(size: size, weight: weight, design: .monospaced)
        case .rounded:
            return .system(size: size, weight: weight, design: .rounded).monospacedDigit()
        }
    }
}

/// Settings for the progress bar appearance.
struct ProgressBarSettings: Codable, Hashable, Sendable {
    /// Color for the played portion of the progress bar.
    var playedColor: CodableColor

    /// Whether to show chapter markers on the progress bar.
    var showChapters: Bool

    /// Settings for SponsorBlock segment display.
    var sponsorBlockSettings: SponsorBlockSegmentSettings

    /// Creates progress bar settings.
    /// - Parameters:
    ///   - playedColor: Color for the played portion. Defaults to red.
    ///   - showChapters: Whether to show chapter markers. Defaults to `true`.
    ///   - sponsorBlockSettings: Settings for SponsorBlock segments. Defaults to `.default`.
    init(
        playedColor: CodableColor = CodableColor(.red),
        showChapters: Bool = true,
        sponsorBlockSettings: SponsorBlockSegmentSettings = .default
    ) {
        self.playedColor = playedColor
        self.showChapters = showChapters
        self.sponsorBlockSettings = sponsorBlockSettings
    }

    /// Default progress bar settings.
    static let `default` = ProgressBarSettings()
}

/// Global settings that apply to all control buttons.
struct GlobalLayoutSettings: Codable, Hashable, Sendable {
    /// Overall style for player controls.
    var style: ControlsStyle

    /// Size of control buttons.
    var buttonSize: ButtonSize

    /// Font style for text elements in player controls.
    var fontStyle: ControlsFontStyle

    /// Opacity of the controls background fade (0-1).
    var controlsFadeOpacity: Double

    /// Mode for system control buttons (Control Center, Lock Screen).
    var systemControlsMode: SystemControlsMode

    /// Duration for seek operations when systemControlsMode is .seek.
    var systemControlsSeekDuration: SystemControlsSeekDuration

    /// How volume is controlled during playback.
    var volumeMode: VolumeMode

    /// Theme derived from style (for backwards compatibility).
    var theme: ControlsTheme { style.theme }

    /// Button background derived from style (for backwards compatibility).
    var buttonBackground: ButtonBackgroundStyle { style.buttonBackground }

    /// Cached settings for instant access (avoids flash on view recreation).
    /// Updated whenever settings are loaded from the active preset.
    nonisolated(unsafe) static var cached: GlobalLayoutSettings = .default

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case style
        case buttonSize
        case buttonBackground // Legacy, not used for encoding
        case theme // Legacy, not used for encoding
        case fontStyle
        case controlsFadeOpacity
        case systemControlsMode
        case systemControlsSeekDuration
        case volumeMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        style = try container.decodeIfPresent(ControlsStyle.self, forKey: .style) ?? .glass
        buttonSize = try container.decodeIfPresent(ButtonSize.self, forKey: .buttonSize) ?? .medium
        fontStyle = try container.decodeIfPresent(ControlsFontStyle.self, forKey: .fontStyle) ?? .system
        controlsFadeOpacity = try container.decodeIfPresent(Double.self, forKey: .controlsFadeOpacity) ?? 0.5
        systemControlsMode = try container.decodeIfPresent(SystemControlsMode.self, forKey: .systemControlsMode) ?? .seek
        systemControlsSeekDuration = try container.decodeIfPresent(SystemControlsSeekDuration.self, forKey: .systemControlsSeekDuration) ?? .tenSeconds
        volumeMode = try container.decodeIfPresent(VolumeMode.self, forKey: .volumeMode) ?? .mpv
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(style, forKey: .style)
        try container.encode(buttonSize, forKey: .buttonSize)
        try container.encode(fontStyle, forKey: .fontStyle)
        try container.encode(controlsFadeOpacity, forKey: .controlsFadeOpacity)
        try container.encode(systemControlsMode, forKey: .systemControlsMode)
        try container.encode(systemControlsSeekDuration, forKey: .systemControlsSeekDuration)
        try container.encode(volumeMode, forKey: .volumeMode)
    }

    // MARK: - Initialization

    /// Creates global layout settings.
    init(
        style: ControlsStyle = .glass,
        buttonSize: ButtonSize = .medium,
        fontStyle: ControlsFontStyle = .system,
        controlsFadeOpacity: Double = 0.5,
        systemControlsMode: SystemControlsMode = .seek,
        systemControlsSeekDuration: SystemControlsSeekDuration = .tenSeconds,
        volumeMode: VolumeMode = .mpv
    ) {
        self.style = style
        self.buttonSize = buttonSize
        self.fontStyle = fontStyle
        self.controlsFadeOpacity = controlsFadeOpacity
        self.systemControlsMode = systemControlsMode
        self.systemControlsSeekDuration = systemControlsSeekDuration
        self.volumeMode = volumeMode
    }

    // MARK: - Defaults

    /// Default global layout settings.
    static let `default` = GlobalLayoutSettings()
}
