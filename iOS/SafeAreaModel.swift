import Foundation
import SwiftUI

final class SafeAreaModel: ObservableObject {
    static var shared = SafeAreaModel()
    @Published var safeArea = EdgeInsets()

    var horizontalInsets: Double {
        safeArea.leading + safeArea.trailing
    }

    var verticalInsets: Double {
        safeArea.top + safeArea.bottom
    }
}
