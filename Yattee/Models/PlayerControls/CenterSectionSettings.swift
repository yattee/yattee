//
//  CenterSectionSettings.swift
//  Yattee
//
//  Settings for the center section of player controls (play/pause, seek buttons).
//

import Foundation

/// Configuration for the center section of player controls.
/// Unlike top/bottom sections, center uses simple toggles rather than drag-and-drop.
struct CenterSectionSettings: Codable, Hashable, Sendable {
    /// Whether to show the play/pause button.
    var showPlayPause: Bool

    /// Whether to show the seek backward button.
    var showSeekBackward: Bool

    /// Whether to show the seek forward button.
    var showSeekForward: Bool

    /// Number of seconds for the seek backward button.
    var seekBackwardSeconds: Int

    /// Number of seconds for the seek forward button.
    var seekForwardSeconds: Int

    /// Type of slider to show on the left edge of the player (iOS only).
    var leftSlider: SideSliderType

    /// Type of slider to show on the right edge of the player (iOS only).
    var rightSlider: SideSliderType

    // MARK: - Initialization

    /// Creates center section settings.
    /// - Parameters:
    ///   - showPlayPause: Show play/pause button. Defaults to true.
    ///   - showSeekBackward: Show seek backward button. Defaults to true.
    ///   - showSeekForward: Show seek forward button. Defaults to true.
    ///   - seekBackwardSeconds: Seconds to seek backward. Defaults to 10.
    ///   - seekForwardSeconds: Seconds to seek forward. Defaults to 10.
    ///   - leftSlider: Type of slider on left edge. Defaults to disabled.
    ///   - rightSlider: Type of slider on right edge. Defaults to disabled.
    init(
        showPlayPause: Bool = true,
        showSeekBackward: Bool = true,
        showSeekForward: Bool = true,
        seekBackwardSeconds: Int = 10,
        seekForwardSeconds: Int = 10,
        leftSlider: SideSliderType = .disabled,
        rightSlider: SideSliderType = .disabled
    ) {
        self.showPlayPause = showPlayPause
        self.showSeekBackward = showSeekBackward
        self.showSeekForward = showSeekForward
        self.seekBackwardSeconds = max(1, seekBackwardSeconds)
        self.seekForwardSeconds = max(1, seekForwardSeconds)
        self.leftSlider = leftSlider
        self.rightSlider = rightSlider
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case showPlayPause
        case showSeekBackward
        case showSeekForward
        case seekBackwardSeconds
        case seekForwardSeconds
        case leftSlider
        case rightSlider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showPlayPause = try container.decode(Bool.self, forKey: .showPlayPause)
        showSeekBackward = try container.decode(Bool.self, forKey: .showSeekBackward)
        showSeekForward = try container.decode(Bool.self, forKey: .showSeekForward)
        seekBackwardSeconds = try container.decode(Int.self, forKey: .seekBackwardSeconds)
        seekForwardSeconds = try container.decode(Int.self, forKey: .seekForwardSeconds)
        // New properties with defaults for backward compatibility
        leftSlider = try container.decodeIfPresent(SideSliderType.self, forKey: .leftSlider) ?? .disabled
        rightSlider = try container.decodeIfPresent(SideSliderType.self, forKey: .rightSlider) ?? .disabled
    }

    // MARK: - Defaults

    /// Default center section settings.
    static let `default` = CenterSectionSettings()

    // MARK: - SF Symbol Names

    /// Seek seconds that have dedicated SF Symbol icons.
    private static let validSeekIconValues = [5, 10, 15, 30, 45, 60, 75, 90]

    /// SF Symbol name for the seek backward button based on configured seconds.
    /// Uses numbered icon for standard values (5, 10, 15, 30, 45, 60, 75, 90),
    /// plain arrow for other values.
    var seekBackwardSystemImage: String {
        if Self.validSeekIconValues.contains(seekBackwardSeconds) {
            return "\(seekBackwardSeconds).arrow.trianglehead.counterclockwise"
        }
        return "arrow.trianglehead.counterclockwise"
    }

    /// SF Symbol name for the seek forward button based on configured seconds.
    /// Uses numbered icon for standard values (5, 10, 15, 30, 45, 60, 75, 90),
    /// plain arrow for other values.
    var seekForwardSystemImage: String {
        if Self.validSeekIconValues.contains(seekForwardSeconds) {
            return "\(seekForwardSeconds).arrow.trianglehead.clockwise"
        }
        return "arrow.trianglehead.clockwise"
    }
}
