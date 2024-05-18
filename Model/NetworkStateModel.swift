import Foundation

final class NetworkStateModel: ObservableObject {
    static var shared = NetworkStateModel()

    @Published var pausedForCache = false
    @Published var cacheDuration = 0.0
    @Published var bufferingState = 0.0

    private var player: PlayerModel! { .shared }
    private let controlsOverlayModel = ControlOverlaysModel.shared

    var osdVisible: Bool {
        guard let player else { return false }
        return player.isPlaying && ((player.activeBackend == .mpv && pausedForCache) || player.isSeeking) && bufferingState < 100.0
    }

    var fullStateText: String? {
        guard let bufferingStateText,
              let cacheDurationText
        else {
            return nil
        }

        return "\(bufferingStateText) (\(cacheDurationText))"
    }

    var bufferingStateText: String? {
        guard detailsAvailable && player.hasStarted else { return nil }
        return String(format: "%.0f%%", bufferingState)
    }

    var cacheDurationText: String? {
        guard detailsAvailable else { return nil }
        return String(format: "%.2fs", cacheDuration)
    }

    var detailsAvailable: Bool {
        guard let player else { return false }
        return player.activeBackend.supportsNetworkStateBufferingDetails
    }

    var needsUpdates: Bool {
        if let player {
            return !player.currentItem.isNil && (pausedForCache || player.isSeeking || player.isLoadingVideo || controlsOverlayModel.presenting)
        }

        return false
    }
}
