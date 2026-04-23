//
//  MiniPlayerSettings.swift
//  Yattee
//
//  Settings for the mini player component.
//

import Foundation
import SwiftUI

// MARK: - MiniPlayerSettings

/// Complete settings for the mini player component.
/// Note: Minimize behavior is intentionally NOT stored here as it's a system UI setting
/// that configures the tab bar and needs to be available synchronously at view creation time.
/// The minimize behavior remains in SettingsManager for the tab bar to access directly.
struct MiniPlayerSettings: Codable, Hashable, Sendable {
    /// Whether to show video preview in the mini player.
    var showVideo: Bool

    /// Action to perform when tapping on the video preview.
    var videoTapAction: MiniPlayerVideoTapAction

    /// Ordered list of buttons to display in the mini player.
    var buttons: [ControlButtonConfiguration]

    // MARK: - Initialization

    init(
        showVideo: Bool = true,
        videoTapAction: MiniPlayerVideoTapAction = .startPiP,
        buttons: [ControlButtonConfiguration] = MiniPlayerSettings.defaultButtons
    ) {
        self.showVideo = showVideo
        self.videoTapAction = videoTapAction
        self.buttons = buttons
    }

    // MARK: - Mutation Helpers

    /// Adds a button of the given type to the mini player.
    /// - Parameter buttonType: The type of button to add.
    mutating func add(buttonType: ControlButtonType) {
        let config = ControlButtonConfiguration(buttonType: buttonType)
        buttons.append(config)
    }

    /// Removes the button at the given index.
    /// - Parameter index: The index of the button to remove.
    mutating func remove(at index: Int) {
        guard buttons.indices.contains(index) else { return }
        buttons.remove(at: index)
    }

    /// Moves buttons within the list.
    /// - Parameters:
    ///   - source: Source indices to move from.
    ///   - destination: Destination index to move to.
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        buttons.move(fromOffsets: source, toOffset: destination)
    }

    /// Updates a button configuration by matching ID.
    /// - Parameter configuration: The updated configuration.
    mutating func update(_ configuration: ControlButtonConfiguration) {
        guard let index = buttons.firstIndex(where: { $0.id == configuration.id }) else { return }
        buttons[index] = configuration
    }

    // MARK: - Default Configuration

    /// Default buttons for the mini player: play/pause and play next.
    private static let defaultButtons: [ControlButtonConfiguration] = [
        ControlButtonConfiguration(buttonType: .playPause),
        ControlButtonConfiguration(buttonType: .playNext),
        ControlButtonConfiguration(buttonType: .close)
    ]

    /// Default mini player settings.
    static let `default` = MiniPlayerSettings()

    /// Cached settings for instant access (avoids flash on view recreation).
    /// Updated whenever settings are loaded from the active preset.
    nonisolated(unsafe) static var cached: MiniPlayerSettings = .default
}
