//
//  Color+Hex.swift
//  Yattee
//
//  Hex-string parsing/formatting for SwiftUI Color, plus the environment value
//  used to drive position-based colorful shortcut cards.
//

import SwiftUI

extension Color {
    /// Creates a color from a `#RRGGBB` / `RRGGBB` hex string (also accepts
    /// `#RGB` shorthand and an optional `AA`/`AARRGGBB`/`RRGGBBAA` alpha).
    /// Returns `nil` for anything it can't parse so bad input is simply skipped.
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isHexDigit }) else { return nil }

        // Expand #RGB shorthand to #RRGGBB.
        if cleaned.count == 3 {
            cleaned = cleaned.map { "\($0)\($0)" }.joined()
        }

        guard let value = UInt64(cleaned, radix: 16) else { return nil }

        let r, g, b, a: Double
        switch cleaned.count {
        case 6: // RRGGBB
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
            a = 1
        case 8: // RRGGBBAA
            r = Double((value & 0xFF00_0000) >> 24) / 255
            g = Double((value & 0x00FF_0000) >> 16) / 255
            b = Double((value & 0x0000_FF00) >> 8) / 255
            a = Double(value & 0x0000_00FF) / 255
        default:
            return nil
        }

        self.init(red: r, green: g, blue: b, opacity: a)
    }

    /// Formats the resolved color as an uppercase `#RRGGBB` string.
    func toHexString() -> String {
        let resolved = resolve(in: EnvironmentValues())
        let r = Int((max(0, min(1, resolved.red)) * 255).rounded())
        let g = Int((max(0, min(1, resolved.green)) * 255).rounded())
        let b = Int((max(0, min(1, resolved.blue)) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Environment: position-based colorful color

private struct HomeShortcutColorfulColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    /// The colorful-style fill color resolved from the shortcut's grid position.
    /// When set, it overrides a card's fixed `colorfulColor`.
    var homeShortcutColorfulColor: Color? {
        get { self[HomeShortcutColorfulColorKey.self] }
        set { self[HomeShortcutColorfulColorKey.self] = newValue }
    }
}
