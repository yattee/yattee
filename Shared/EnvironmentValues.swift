import Foundation
import SwiftUI

private struct InNavigationViewKey: EnvironmentKey {
    static let defaultValue = false
}

private struct InChannelViewKey: EnvironmentKey {
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

extension EnvironmentValues {
    var inNavigationView: Bool {
        get { self[InNavigationViewKey.self] }
        set { self[InNavigationViewKey.self] = newValue }
    }

    var inChannelView: Bool {
        get { self[InChannelViewKey.self] }
        set { self[InChannelViewKey.self] = newValue }
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
}
