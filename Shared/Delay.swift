import Foundation

enum Delay {
    @discardableResult static func by(_ interval: TimeInterval, block: @escaping () -> Void) -> Timer {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in block() }
    }
}
