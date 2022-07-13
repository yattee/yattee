import Defaults
import Foundation

enum PlayerBackendType: String, CaseIterable, Defaults.Serializable {
    case mpv
    case appleAVPlayer

    var label: String {
        switch self {
        case .mpv:
            return "MPV"
        case .appleAVPlayer:
            return "AVPlayer"
        }
    }

    var supportsNetworkStateBufferingDetails: Bool {
        self == .mpv
    }
}
