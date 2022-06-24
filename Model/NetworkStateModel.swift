import Foundation

final class NetworkStateModel: ObservableObject {
    @Published var pausedForCache = false
    @Published var cacheDuration = 0.0
    @Published var bufferingState = 0.0

    var player: PlayerModel!

    var fullStateText: String? {
        guard let bufferingStateText = bufferingStateText,
              let cacheDurationText = cacheDurationText
        else {
            return nil
        }

        return "\(bufferingStateText) (\(cacheDurationText))"
    }

    var bufferingStateText: String? {
        guard detailsAvailable else { return nil }
        return String(format: "%.0f%%", bufferingState)
    }

    var cacheDurationText: String? {
        guard detailsAvailable else { return nil }
        return String(format: "%.2fs", cacheDuration)
    }

    var detailsAvailable: Bool {
        guard let player = player else { return false }
        return player.activeBackend.supportsNetworkStateBufferingDetails
    }

    var needsUpdates: Bool {
        if let player = player {
            return pausedForCache || player.isSeeking || player.isLoadingVideo || player.controls.presentingControlsOverlay
        }

        return pausedForCache
    }
}
