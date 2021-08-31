import Foundation
import SwiftUI

private struct InNavigationViewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var inNavigationView: Bool {
        get { self[InNavigationViewKey.self] }
        set { self[InNavigationViewKey.self] = newValue }
    }
}
