import Foundation

enum StreamType: String, Comparable {
    case stream, adaptive

    private var sortOrder: Int {
        switch self {
        case .stream:
            return 0
        case .adaptive:
            return 1
        }
    }

    static func < (lhs: StreamType, rhs: StreamType) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}
