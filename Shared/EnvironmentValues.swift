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

private struct CurrentPlaylistID: EnvironmentKey {
    static let defaultValue: String? = nil
}

typealias LoadMoreContentHandlerType = () -> Void

private struct LoadMoreContentHandler: EnvironmentKey {
    static let defaultValue: LoadMoreContentHandlerType = {}
}

private struct ScrollViewBottomPaddingKey: EnvironmentKey {
    static let defaultValue: Double = 30
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

    var scrollViewBottomPadding: Double {
        get { self[ScrollViewBottomPaddingKey.self] }
        set { self[ScrollViewBottomPaddingKey.self] = newValue }
    }
}
