import CoreMedia
import Foundation
import SwiftUI

final class PlayerControlsModel: ObservableObject {
    @Published var isLoadingVideo = true
    @Published var isPlaying = true
    @Published var currentTime = CMTime.zero
    @Published var duration = CMTime.zero
    @Published var presentingControls = false { didSet { handlePresentationChange() } }
    @Published var timer: Timer?
    @Published var playingFullscreen = false

    var player: PlayerModel!

    var playbackTime: String {
        guard let current = currentTime.seconds.formattedAsPlaybackTime(),
              let duration = duration.seconds.formattedAsPlaybackTime()
        else {
            return "--:-- / --:--"
        }

        var withoutSegments = ""
        if let withoutSegmentsDuration = playerItemDurationWithoutSponsorSegments,
           self.duration.seconds != withoutSegmentsDuration
        {
            withoutSegments = " (\(withoutSegmentsDuration.formattedAsPlaybackTime() ?? "--:--"))"
        }

        return "\(current) / \(duration)\(withoutSegments)"
    }

    var playerItemDurationWithoutSponsorSegments: Double? {
        guard let duration = player.playerItemDurationWithoutSponsorSegments else {
            return nil
        }

        return duration.seconds
    }

    func handlePresentationChange() {
        if presentingControls {
            DispatchQueue.main.async { [weak self] in
                self?.player.backend.startControlsUpdates()
                self?.resetTimer()
            }
        } else {
            player.backend.stopControlsUpdates()
            timer?.invalidate()
            timer = nil
        }
    }

    func show() {
        withAnimation(PlayerControls.animation) {
            player.backend.updateControls()
            presentingControls = true
        }
    }

    func hide() {
        withAnimation(PlayerControls.animation) {
            presentingControls = false
        }
    }

    func toggle() {
        withAnimation(PlayerControls.animation) {
            if !presentingControls {
                player.backend.updateControls()
            }

            presentingControls.toggle()
        }
    }

    func toggleFullscreen(_ value: Bool) {
        withAnimation(Animation.easeOut) {
            resetTimer()
            withAnimation(PlayerControls.animation) {
                playingFullscreen = !value
            }

            if playingFullscreen {
                guard !(UIApplication.shared.windows.first?.windowScene?.interfaceOrientation.isLandscape ?? true) else {
                    return
                }
                Orientation.lockOrientation(.landscape, andRotateTo: .landscapeRight)
            } else {
                Orientation.lockOrientation(.allButUpsideDown, andRotateTo: .portrait)
            }
        }
    }

    func reset() {
        currentTime = .zero
        duration = .zero
    }

    func resetTimer() {
        removeTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            withAnimation(PlayerControls.animation) { [weak self] in
                self?.presentingControls = false
                self?.player.backend.stopControlsUpdates()
            }
        }
    }

    func removeTimer() {
        timer?.invalidate()
        timer = nil
    }
}
