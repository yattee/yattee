import Foundation

struct Debounce {
    private var timer: Timer?

    mutating func debouncing(_ interval: TimeInterval, action: @escaping () -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            action()
        }
    }

    func invalidate() {
        timer?.invalidate()
    }
}
