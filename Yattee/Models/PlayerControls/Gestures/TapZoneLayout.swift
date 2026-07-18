//
//  TapZoneLayout.swift
//  Yattee
//
//  Defines the available tap zone layouts for gesture recognition.
//

import Foundation

/// Layout options for tap gesture zones on the player.
enum TapZoneLayout: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Single full-screen zone.
    case single

    /// Left and right zones (vertical split).
    case horizontalSplit

    /// Top and bottom zones (horizontal split).
    case verticalSplit

    /// Three vertical columns: left, center, right.
    case threeColumns

    /// Four quadrants: top-left, top-right, bottom-left, bottom-right.
    case quadrants

    var id: String { rawValue }

    /// Number of zones in this layout.
    var zoneCount: Int {
        switch self {
        case .single:
            1
        case .horizontalSplit, .verticalSplit:
            2
        case .threeColumns:
            3
        case .quadrants:
            4
        }
    }

    /// The zone positions available in this layout.
    var positions: [TapZonePosition] {
        switch self {
        case .single:
            [.full]
        case .horizontalSplit:
            [.left, .right]
        case .verticalSplit:
            [.top, .bottom]
        case .threeColumns:
            [.leftThird, .center, .rightThird]
        case .quadrants:
            [.topLeft, .topRight, .bottomLeft, .bottomRight]
        }
    }

    /// Display name for the layout.
    var displayName: String {
        switch self {
        case .single:
            String(localized: "gestures.layout.single", defaultValue: "Single Zone")
        case .horizontalSplit:
            String(localized: "gestures.layout.horizontalSplit", defaultValue: "Left / Right")
        case .verticalSplit:
            String(localized: "gestures.layout.verticalSplit", defaultValue: "Top / Bottom")
        case .threeColumns:
            String(localized: "gestures.layout.threeColumns", defaultValue: "Three Columns")
        case .quadrants:
            String(localized: "gestures.layout.quadrants", defaultValue: "Four Quadrants")
        }
    }

    /// Short description showing zone arrangement.
    var layoutDescription: String {
        switch self {
        case .single:
            "1"
        case .horizontalSplit:
            "2x1"
        case .verticalSplit:
            "1x2"
        case .threeColumns:
            "1x3"
        case .quadrants:
            "2x2"
        }
    }
}
