//
//  SideSliderType.swift
//  Yattee
//
//  Type of control for vertical side sliders in player controls.
//

import Foundation

/// Type of control for vertical side sliders in player.
/// Used for configuring left and right edge sliders in center controls settings.
enum SideSliderType: String, Codable, Hashable, Sendable, CaseIterable {
    /// No slider shown on this side.
    case disabled

    /// Volume control slider.
    case volume

    /// Screen brightness control slider.
    case brightness

    // MARK: - Display Properties

    /// Localized display name for the slider type.
    var displayName: String {
        switch self {
        case .disabled:
            String(localized: "sideSlider.disabled")
        case .volume:
            String(localized: "sideSlider.volume")
        case .brightness:
            String(localized: "sideSlider.brightness")
        }
    }

    /// SF Symbol icon for the slider type, or nil if disabled.
    var systemImage: String? {
        switch self {
        case .disabled:
            nil
        case .volume:
            "speaker.wave.2.fill"
        case .brightness:
            "sun.max.fill"
        }
    }
}
