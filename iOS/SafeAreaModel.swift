import Foundation
import SwiftUI

final class SafeAreaModel: ObservableObject {
    static var shared = SafeAreaModel()
    @Published var safeArea = EdgeInsets()
}
