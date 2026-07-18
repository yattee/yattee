//
//  PlayerPillSettings.swift
//  Yattee
//
//  Settings for the player pill component (visibility and buttons).
//

import Foundation
import SwiftUI

// MARK: - CommentsPillMode

/// Controls how the comments pill is displayed in the player.
enum CommentsPillMode: String, Codable, Hashable, Sendable, CaseIterable {
    case pill       // Default - shows expanded pill, collapses on scroll
    case button     // Always show collapsed (button-only)
    case disabled   // No button/pill visible, no API query

    /// Localized display name for settings UI.
    var displayName: String {
        switch self {
        case .pill:
            return String(localized: "commentsPill.mode.pill")
        case .button:
            return String(localized: "commentsPill.mode.button")
        case .disabled:
            return String(localized: "commentsPill.mode.disabled")
        }
    }

    /// Whether comments should be loaded from the API.
    var shouldLoadComments: Bool {
        self != .disabled
    }

    /// Whether the comments pill should always be collapsed (button mode).
    var alwaysCollapsed: Bool {
        self == .button
    }
}

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

    /// How the comments pill should be displayed (optional for backward compatibility).
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

    // MARK: - Computed Properties

    /// Returns the effective comments pill mode, defaulting to `.pill` when nil.
    var effectiveCommentsPillMode: CommentsPillMode {
        commentsPillMode ?? .pill
    }

    /// Whether comments should be loaded from the API.
    var shouldLoadComments: Bool {
        effectiveCommentsPillMode.shouldLoadComments
    }

    /// Whether the comments pill should always be shown collapsed.
    var isCommentsPillAlwaysCollapsed: Bool {
        effectiveCommentsPillMode.alwaysCollapsed
    }

    /// Whether the comments pill should be visible at all.
    var shouldShowCommentsPill: Bool {
        effectiveCommentsPillMode != .disabled
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
