//
//  SourcesSettings.swift
//  Yattee
//
//  Local-only settings for sources sorting and grouping.
//  These settings are NOT synced to iCloud.
//

import Foundation

/// Sort options for sources.
enum SourcesSortOption: String, CaseIterable, Codable {
    case name
    case type
    case dateAdded

    var displayName: String {
        switch self {
        case .name:
            return String(localized: "sources.sort.name")
        case .type:
            return String(localized: "sources.sort.type")
        case .dateAdded:
            return String(localized: "sources.sort.dateAdded")
        }
    }

    var systemImage: String {
        switch self {
        case .name:
            return "textformat"
        case .type:
            return "square.grid.2x2"
        case .dateAdded:
            return "calendar"
        }
    }
}

/// Manages sources view settings locally (not synced to iCloud).
@MainActor
@Observable
final class SourcesSettings {
    // MARK: - Storage Keys

    private enum Keys {
        static let sortOption = "sources.sortOption"
        static let sortDirection = "sources.sortDirection"
        static let groupByType = "sources.groupByType"
    }

    // MARK: - Storage

    private let defaults = UserDefaults.standard

    // MARK: - Cached Values

    private var _sortOption: SourcesSortOption?
    private var _sortDirection: SortDirection?
    private var _groupByType: Bool?

    // MARK: - Properties

    /// The current sort option for sources.
    var sortOption: SourcesSortOption {
        get {
            if let cached = _sortOption { return cached }
            guard let rawValue = defaults.string(forKey: Keys.sortOption),
                  let option = SourcesSortOption(rawValue: rawValue) else {
                return .name
            }
            return option
        }
        set {
            _sortOption = newValue
            defaults.set(newValue.rawValue, forKey: Keys.sortOption)
        }
    }

    /// The current sort direction.
    var sortDirection: SortDirection {
        get {
            if let cached = _sortDirection { return cached }
            guard let rawValue = defaults.string(forKey: Keys.sortDirection),
                  let direction = SortDirection(rawValue: rawValue) else {
                return .ascending
            }
            return direction
        }
        set {
            _sortDirection = newValue
            defaults.set(newValue.rawValue, forKey: Keys.sortDirection)
        }
    }

    /// Whether to group sources by type.
    var groupByType: Bool {
        get {
            if let cached = _groupByType { return cached }
            // Default to true if not set
            if defaults.object(forKey: Keys.groupByType) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.groupByType)
        }
        set {
            _groupByType = newValue
            defaults.set(newValue, forKey: Keys.groupByType)
        }
    }

    // MARK: - Sorting

    /// Sorts an array of instances based on current settings.
    func sorted(_ instances: [Instance]) -> [Instance] {
        instances.sorted { first, second in
            let comparison: Bool
            switch sortOption {
            case .name:
                comparison = first.displayName.localizedCaseInsensitiveCompare(second.displayName) == .orderedAscending
            case .type:
                comparison = first.type.displayName.localizedCaseInsensitiveCompare(second.type.displayName) == .orderedAscending
            case .dateAdded:
                comparison = first.dateAdded < second.dateAdded
            }
            return sortDirection == .ascending ? comparison : !comparison
        }
    }

    /// Sorts an array of media sources based on current settings.
    func sorted(_ sources: [MediaSource]) -> [MediaSource] {
        sources.sorted { first, second in
            let comparison: Bool
            switch sortOption {
            case .name:
                comparison = first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
            case .type:
                comparison = first.type.displayName.localizedCaseInsensitiveCompare(second.type.displayName) == .orderedAscending
            case .dateAdded:
                comparison = first.dateAdded < second.dateAdded
            }
            return sortDirection == .ascending ? comparison : !comparison
        }
    }

    /// Returns available sort options based on current grouping state.
    /// When grouped by type, the "type" sort option is hidden.
    var availableSortOptions: [SourcesSortOption] {
        if groupByType {
            return [.name, .dateAdded]
        }
        return SourcesSortOption.allCases
    }
}
