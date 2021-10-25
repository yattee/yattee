import Foundation

final class Throttle {
    let interval: TimeInterval
    private(set) var lastExecutedAt: Date?

    private let syncQueue = DispatchQueue(label: "net.yatee.app.throttle")

    init(interval: TimeInterval) {
        self.interval = interval
    }

    @discardableResult func execute(_ action: () -> Void) -> Bool {
        let executed = syncQueue.sync { () -> Bool in
            let now = Date()

            let timeInterval = now.timeIntervalSince(lastExecutedAt ?? .distantPast)

            if timeInterval > interval {
                lastExecutedAt = now

                return true
            }

            return false
        }

        if executed {
            action()
        }

        return executed
    }

    func reset() {
        syncQueue.sync {
            lastExecutedAt = nil
        }
    }
}
