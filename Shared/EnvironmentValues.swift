import Foundation
import SwiftUI

private struct InNavigationViewKey: EnvironmentKey {
    static let defaultValue = false
}

private struct HorizontalCellsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var inNavigationView: Bool {
        get { self[InNavigationViewKey.self] }
        set { self[InNavigationViewKey.self] = newValue }
    }

    var horizontalCells: Bool {
        get { self[HorizontalCellsKey.self] }
        set { self[HorizontalCellsKey.self] = newValue }
    }
}
