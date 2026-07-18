//
//  TapZonePosition.swift
//  Yattee
//
//  Defines the position identifiers for tap zones.
//

import Foundation

/// Position identifier for a tap zone within a layout.
enum TapZonePosition: String, Codable, CaseIterable, Sendable, Identifiable {
    // Single layout
    case full

    // Horizontal split (2x1)
    case left
    case right

    // Vertical split (1x2)
    case top
    case bottom

    // Three columns (1x3)
    case leftThird
    case center
    case rightThird

    // Quadrants (2x2)
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    /// Display name for the zone position.
    var displayName: String {
        switch self {
        case .full:
            String(localized: "gestures.zone.full", defaultValue: "Tap Zone")
        case .left:
            String(localized: "gestures.zone.left", defaultValue: "Left")
        case .right:
            String(localized: "gestures.zone.right", defaultValue: "Right")
        case .top:
            String(localized: "gestures.zone.top", defaultValue: "Top")
        case .bottom:
            String(localized: "gestures.zone.bottom", defaultValue: "Bottom")
        case .leftThird:
            String(localized: "gestures.zone.leftThird", defaultValue: "Left")
        case .center:
            String(localized: "gestures.zone.center", defaultValue: "Center")
        case .rightThird:
            String(localized: "gestures.zone.rightThird", defaultValue: "Right")
        case .topLeft:
            String(localized: "gestures.zone.topLeft", defaultValue: "Top-Left")
        case .topRight:
            String(localized: "gestures.zone.topRight", defaultValue: "Top-Right")
        case .bottomLeft:
            String(localized: "gestures.zone.bottomLeft", defaultValue: "Bottom-Left")
        case .bottomRight:
            String(localized: "gestures.zone.bottomRight", defaultValue: "Bottom-Right")
        }
    }
}
