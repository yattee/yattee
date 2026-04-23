//
//  SubtitleSettings.swift
//  Yattee
//
//  Settings for subtitle appearance in MPV player.
//

import Foundation

// MARK: - Subtitle Font

/// Font options for subtitles.
enum SubtitleFont: String, Codable, Hashable, Sendable, CaseIterable {
    case sansSerif
    case serif
    case monospaced

    /// Display name for the UI.
    var displayName: String {
        switch self {
        case .sansSerif:
            return String(localized: "settings.subtitles.font.sansSerif")
        case .serif:
            return String(localized: "settings.subtitles.font.serif")
        case .monospaced:
            return String(localized: "settings.subtitles.font.monospaced")
        }
    }

    /// MPV font name for this font option.
    var mpvFontName: String {
        switch self {
        case .sansSerif:
            return "sans-serif"
        case .serif:
            return "serif"
        case .monospaced:
            return "monospace"
        }
    }

}


// MARK: - Subtitle Settings

/// Settings for subtitle appearance in MPV.
struct SubtitleSettings: Codable, Hashable, Sendable {
    /// Font for subtitles.
    var font: SubtitleFont

    /// Font size for subtitles (in points, 20-100).
    var fontSize: Int

    /// Text color for subtitles.
    var textColor: CodableColor

    /// Border (outline) color for subtitles.
    var borderColor: CodableColor

    /// Border size (0-5).
    var borderSize: Double

    /// Background color for subtitles (when showBackground is enabled).
    var backgroundColor: CodableColor

    /// Whether to show a background box behind subtitles.
    var showBackground: Bool

    /// Whether text is bold.
    var isBold: Bool

    /// Whether text is italic.
    var isItalic: Bool

    /// Bottom margin as percentage (0-50).
    var bottomMargin: Int

    /// Creates subtitle settings with default values.
    init(
        font: SubtitleFont = .sansSerif,
        fontSize: Int = 60,
        textColor: CodableColor = CodableColor(red: 1, green: 1, blue: 1),
        borderColor: CodableColor = CodableColor(red: 0, green: 0, blue: 0),
        borderSize: Double = 2.5,
        backgroundColor: CodableColor = CodableColor(red: 0, green: 0, blue: 0, opacity: 0.75),
        showBackground: Bool = false,
        isBold: Bool = false,
        isItalic: Bool = false,
        bottomMargin: Int = 30
    ) {
        self.font = font
        self.fontSize = fontSize
        self.textColor = textColor
        self.borderColor = borderColor
        self.borderSize = borderSize
        self.backgroundColor = backgroundColor
        self.showBackground = showBackground
        self.isBold = isBold
        self.isItalic = isItalic
        self.bottomMargin = bottomMargin
    }

    /// Default subtitle settings.
    static let `default` = SubtitleSettings()

    /// Converts settings to MPV options dictionary.
    /// - Returns: Dictionary of MPV option names to values.
    func mpvOptions() -> [String: String] {
        var options: [String: String] = [:]

        // Font
        options["sub-font"] = font.mpvFontName
        options["sub-font-size"] = String(fontSize)

        // Text color (BBGGRR format for MPV with alpha as separate component)
        options["sub-color"] = mpvColorString(textColor)

        // Border
        options["sub-border-color"] = mpvColorString(borderColor)
        options["sub-border-size"] = String(format: "%.1f", borderSize)

        // Background
        if showBackground {
            options["sub-back-color"] = mpvColorString(backgroundColor)
            options["sub-border-style"] = "background-box"
        } else {
            options["sub-back-color"] = "#00000000"  // Transparent
            options["sub-border-style"] = "outline-and-shadow"  // Default style
        }

        // Style
        options["sub-bold"] = isBold ? "yes" : "no"
        options["sub-italic"] = isItalic ? "yes" : "no"

        // Position
        options["sub-margin-y"] = String(bottomMargin)

        return options
    }

    /// Converts CodableColor to MPV color string format (#AARRGGBB).
    private func mpvColorString(_ color: CodableColor) -> String {
        let r = Int(color.red * 255)
        let g = Int(color.green * 255)
        let b = Int(color.blue * 255)
        let a = Int(color.opacity * 255)
        return String(format: "#%02X%02X%02X%02X", a, r, g, b)
    }
}
