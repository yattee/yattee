import AVFoundation
import Foundation

extension AVKeyValueStatus {
    var string: String {
        switch self {
        case .unknown:
            return "unknown"
        case .loading:
            return "loading"
        case .loaded:
            return "loaded"
        case .failed:
            return "failed"
        case .cancelled:
            return "cancelled"
        @unknown default:
            return "unknown default"
        }
    }
}
