//
//  LayoutSection.swift
//  Yattee
//
//  Represents a section of control buttons in the player layout.
//

import Foundation

/// Identifies a section in the player controls layout.
enum LayoutSectionType: String, Codable, Hashable, Sendable {
    case top
    case bottom
}

/// A section containing an ordered list of control buttons.
struct LayoutSection: Codable, Hashable, Sendable {
    /// The ordered list of button configurations in this section.
    var buttons: [ControlButtonConfiguration]

    // MARK: - Initialization

    /// Creates a new layout section.
    /// - Parameter buttons: The buttons in this section.
    init(buttons: [ControlButtonConfiguration] = []) {
        self.buttons = buttons
    }

    // MARK: - Mutation Helpers

    /// Adds a button to the end of the section.
    /// - Parameter button: The button configuration to add.
    mutating func add(button: ControlButtonConfiguration) {
        buttons.append(button)
    }

    /// Adds a button with the given type to the end of the section.
    /// - Parameter type: The button type to add with default configuration.
    mutating func add(buttonType type: ControlButtonType) {
        buttons.append(.defaultConfiguration(for: type))
    }

    /// Removes a button at the specified index.
    /// - Parameter index: The index of the button to remove.
    mutating func remove(at index: Int) {
        guard buttons.indices.contains(index) else { return }
        buttons.remove(at: index)
    }

    /// Removes a button with the specified ID.
    /// - Parameter id: The ID of the button to remove.
    mutating func remove(id: UUID) {
        buttons.removeAll { $0.id == id }
    }

    /// Moves a button from one position to another.
    /// - Parameters:
    ///   - source: The current index of the button.
    ///   - destination: The target index for the button.
    mutating func move(from source: Int, to destination: Int) {
        guard buttons.indices.contains(source) else { return }
        let button = buttons.remove(at: source)
        let targetIndex = destination > source ? destination - 1 : destination
        let clampedIndex = max(0, min(buttons.count, targetIndex))
        buttons.insert(button, at: clampedIndex)
    }

    /// Moves buttons from source indices to a destination index.
    /// Compatible with SwiftUI's `onMove` modifier.
    /// - Parameters:
    ///   - source: The indices of buttons to move.
    ///   - destination: The target index.
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        // Implement IndexSet-based move manually to avoid SwiftUI dependency
        let itemsToMove = source.map { buttons[$0] }
        var newButtons = buttons.enumerated().filter { !source.contains($0.offset) }.map { $0.element }

        // Adjust destination for removed items
        let adjustedDestination = source.filter { $0 < destination }.count
        let insertIndex = max(0, min(newButtons.count, destination - adjustedDestination))

        newButtons.insert(contentsOf: itemsToMove, at: insertIndex)
        buttons = newButtons
    }

    /// Updates a button configuration.
    /// - Parameter button: The updated button configuration.
    mutating func update(button: ControlButtonConfiguration) {
        guard let index = buttons.firstIndex(where: { $0.id == button.id }) else { return }
        buttons[index] = button
    }

    // MARK: - Query Helpers

    /// Returns the button types currently in this section.
    var buttonTypes: [ControlButtonType] {
        buttons.map(\.buttonType)
    }

    /// Checks if a button type is already in this section.
    /// - Parameter type: The button type to check.
    /// - Returns: True if the type is already present.
    func contains(buttonType type: ControlButtonType) -> Bool {
        buttons.contains { $0.buttonType == type }
    }

    /// Returns buttons filtered by visibility for the given layout state.
    /// - Parameter isWideLayout: Whether the current layout is wide/landscape.
    /// - Returns: Buttons that should be visible.
    func visibleButtons(isWideLayout: Bool) -> [ControlButtonConfiguration] {
        buttons.filter { $0.visibilityMode.isVisible(isWideLayout: isWideLayout) }
    }
}
