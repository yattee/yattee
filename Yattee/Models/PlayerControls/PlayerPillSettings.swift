//
//  PlayerPillSettings.swift
//  Yattee
//
//  Settings for the player pill component (visibility and buttons).
//

import Foundation
import SwiftUI

// MARK: - PillVisibility

/// Controls when the player pill is visible based on orientation.
enum PillVisibility: String, Codable, Hashable, Sendable, CaseIterable {
    case portraitOnly   // Default - shown in portrait orientation only
    case landscapeOnly  // Shown in wide/landscape orientation only
    case both           // Shown in all orientations
    case never          // Pill disabled

    /// Localized display name for settings UI.
    var displayName: String {
        switch self {
        case .portraitOnly:
            return String(localized: "pill.visibility.portraitOnly")
        case .landscapeOnly:
            return String(localized: "pill.visibility.landscapeOnly")
        case .both:
            return String(localized: "pill.visibility.both")
        case .never:
            return String(localized: "pill.visibility.never")
        }
    }

    /// Returns whether the pill should be visible for the given layout context.
    /// - Parameter isWideLayout: True if in wide/landscape layout, false for portrait.
    /// - Returns: Whether the pill should be shown.
    func isVisible(isWideLayout: Bool) -> Bool {
        switch self {
        case .portraitOnly:
            return !isWideLayout
        case .landscapeOnly:
            return isWideLayout
        case .both:
            return true
        case .never:
            return false
        }
    }
}

// MARK: - PlayerPillSettings

/// Complete settings for the player pill component.
struct PlayerPillSettings: Codable, Hashable, Sendable {
    /// When to show the pill.
    var visibility: PillVisibility

    /// Ordered list of buttons to display in the pill.
    var buttons: [ControlButtonConfiguration]

    /// Legacy: the comments pill mode now lives on the comments page settings
    /// (`CommentsPageSettings.pillMode`). Kept only so old presets decode;
    /// `PlayerControlsLayout.effectivePanelSettings` migrates it.
    var commentsPillMode: CommentsPillMode?

    // MARK: - Initialization

    init(
        visibility: PillVisibility = .portraitOnly,
        buttons: [ControlButtonConfiguration] = [],
        commentsPillMode: CommentsPillMode? = nil
    ) {
        self.visibility = visibility
        self.buttons = buttons
        self.commentsPillMode = commentsPillMode
    }

    // MARK: - Mutation Helpers

    /// Adds a button of the given type to the pill.
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

    /// Default player pill settings matching the original queue pill behavior.
    static let `default` = PlayerPillSettings(
        visibility: .portraitOnly,
        buttons: [
            ControlButtonConfiguration(buttonType: .queue),
            ControlButtonConfiguration(buttonType: .playPrevious),
            ControlButtonConfiguration(buttonType: .playPause),
            ControlButtonConfiguration(buttonType: .playNext),
            ControlButtonConfiguration(buttonType: .close)
        ]
    )
}
