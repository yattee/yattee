//
//  VideoListLayout.swift
//  Yattee
//
//  Layout options for video listing views.
//

import SwiftUI

/// Layout type for video lists.
enum VideoListLayout: String, CaseIterable {
    case list
    case grid

    var displayName: LocalizedStringKey {
        switch self {
        case .list: "viewOptions.layout.list"
        case .grid: "viewOptions.layout.grid"
        }
    }

    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        }
    }
}

// MARK: - Grid Layout Helpers

/// Constants for grid layout calculations.
enum GridConstants {
    /// Minimum width for a video card thumbnail to remain usable.
    static let minCardWidth: CGFloat = {
        #if os(tvOS)
        200
        #else
        100
        #endif
    }()

    /// Spacing between grid items.
    static let spacing: CGFloat = {
        #if os(tvOS)
        32
        #else
        12
        #endif
    }()

    /// Horizontal padding for the grid container.
    static let horizontalPadding: CGFloat = 32

    /// Maximum allowed columns (to prevent excessive density).
    static let maxAllowedColumns = 6

    /// Threshold for compact card styling (columns >= this use compact mode).
    static let compactThreshold = 3
}

/// Calculates the maximum number of grid columns that fit within a given width.
/// - Parameters:
///   - width: Available container width
///   - minCardWidth: Minimum width per card (defaults to GridConstants.minCardWidth)
///   - spacing: Spacing between cards (defaults to GridConstants.spacing)
/// - Returns: Maximum columns that fit, clamped between 1 and maxAllowedColumns
func maxGridColumns(
    forWidth width: CGFloat,
    minCardWidth: CGFloat = GridConstants.minCardWidth,
    spacing: CGFloat = GridConstants.spacing
) -> Int {
    let availableWidth = width - GridConstants.horizontalPadding
    // Formula: availableWidth = (columns * minCardWidth) + ((columns - 1) * spacing)
    // Solving for columns: columns = (availableWidth + spacing) / (minCardWidth + spacing)
    let maxColumns = Int((availableWidth + spacing) / (minCardWidth + spacing))
    return max(1, min(maxColumns, GridConstants.maxAllowedColumns))
}

/// Creates grid columns for a LazyVGrid with the specified count.
/// - Parameter count: Number of columns
/// - Returns: Array of flexible GridItems with top alignment
func makeGridColumns(count: Int) -> [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: GridConstants.spacing, alignment: .top), count: max(1, count))
}

// MARK: - Grid Layout Configuration

/// Encapsulates grid layout calculations for views with grid/list layouts.
///
/// Use this to eliminate repeated computed properties across grid-enabled views.
/// Create an instance with the current view width and user-selected column count,
/// then use the computed properties for layout decisions.
///
/// Usage:
/// ```swift
/// @State private var viewWidth: CGFloat = 0
/// @AppStorage("myView.gridColumns") private var gridColumns = 2
///
/// private var gridConfig: GridLayoutConfiguration {
///     GridLayoutConfiguration(viewWidth: viewWidth, gridColumns: gridColumns)
/// }
///
/// // Then use:
/// // gridConfig.effectiveColumns - actual column count
/// // gridConfig.isCompactCards - whether to use compact card styling
/// // gridConfig.columns - GridItem array for LazyVGrid
/// // gridConfig.maxColumns - for ViewOptionsSheet
/// ```
struct GridLayoutConfiguration {
    let viewWidth: CGFloat
    let gridColumns: Int

    /// Maximum columns that fit in the current width.
    var maxColumns: Int {
        maxGridColumns(forWidth: viewWidth)
    }

    /// Effective column count, clamped to valid range.
    var effectiveColumns: Int {
        min(max(1, gridColumns), max(1, maxColumns))
    }

    /// Whether cards should use compact styling (3+ columns).
    var isCompactCards: Bool {
        effectiveColumns >= GridConstants.compactThreshold
    }

    /// GridItem array for LazyVGrid columns parameter.
    var columns: [GridItem] {
        makeGridColumns(count: effectiveColumns)
    }
}
