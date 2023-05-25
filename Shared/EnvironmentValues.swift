import Defaults
import Foundation
import SwiftUI

private struct InChannelViewKey: EnvironmentKey {
    static let defaultValue = false
}

private struct InChannelPlaylistViewKey: EnvironmentKey {
    static let defaultValue = false
}

private struct HorizontalCellsKey: EnvironmentKey {
    static let defaultValue = false
}

enum NavigationStyle {
    case tab, sidebar
}

private struct NavigationStyleKey: EnvironmentKey {
    static let defaultValue = NavigationStyle.tab
}

private struct ListingStyleKey: EnvironmentKey {
    static let defaultValue = ListingStyle.cells
}

private struct InNavigationViewKey: EnvironmentKey {
    static let defaultValue = true
}

private struct InQueueListingKey: EnvironmentKey {
    static let defaultValue = false
}

private struct NoListingDividersKey: EnvironmentKey {
    static let defaultValue = false
}

enum ListingStyle: String, CaseIterable, Defaults.Serializable {
    case cells
    case list

    var systemImage: String {
        switch self {
        case .cells:
            return "rectangle.grid.2x2"
        case .list:
            return "list.dash"
        }
    }
}

private struct CurrentPlaylistID: EnvironmentKey {
    static let defaultValue: String? = nil
}

typealias LoadMoreContentHandlerType = () -> Void

private struct LoadMoreContentHandler: EnvironmentKey {
    static let defaultValue: LoadMoreContentHandlerType = {}
}

extension EnvironmentValues {
    var inChannelView: Bool {
        get { self[InChannelViewKey.self] }
        set { self[InChannelViewKey.self] = newValue }
    }

    var inChannelPlaylistView: Bool {
        get { self[InChannelPlaylistViewKey.self] }
        set { self[InChannelPlaylistViewKey.self] = newValue }
    }

    var horizontalCells: Bool {
        get { self[HorizontalCellsKey.self] }
        set { self[HorizontalCellsKey.self] = newValue }
    }

    var navigationStyle: NavigationStyle {
        get { self[NavigationStyleKey.self] }
        set { self[NavigationStyleKey.self] = newValue }
    }

    var currentPlaylistID: String? {
        get { self[CurrentPlaylistID.self] }
        set { self[CurrentPlaylistID.self] = newValue }
    }

    var loadMoreContentHandler: LoadMoreContentHandlerType {
        get { self[LoadMoreContentHandler.self] }
        set { self[LoadMoreContentHandler.self] = newValue }
    }

    var listingStyle: ListingStyle {
        get { self[ListingStyleKey.self] }
        set { self[ListingStyleKey.self] = newValue }
    }

    var inNavigationView: Bool {
        get { self[InNavigationViewKey.self] }
        set { self[InNavigationViewKey.self] = newValue }
    }

    var inQueueListing: Bool {
        get { self[InQueueListingKey.self] }
        set { self[InQueueListingKey.self] = newValue }
    }

    var noListingDividers: Bool {
        get { self[NoListingDividersKey.self] }
        set { self[NoListingDividersKey.self] = newValue }
    }
}
