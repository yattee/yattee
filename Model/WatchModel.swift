import SwiftUI

final class WatchModel: ObservableObject {
    static let shared = WatchModel()

    @Published var historyToken = UUID()

    func watchesChanged() {
        historyToken = UUID()
    }
}
