import CoreMedia
import Foundation
import SwiftUI

final class PlayerControlsModel: ObservableObject {
    @Published var isLoadingVideo = false
    @Published var isPlaying = true
    @Published var presentingControls = false { didSet { handlePresentationChange() } }
    @Published var presentingControlsOverlay = false
    @Published var timer: Timer?

    var player: PlayerModel!

    init(
        isLoadingVideo: Bool = false,
        isPlaying: Bool = true,
        presentingControls: Bool = false,
        presentingControlsOverlay: Bool = false,
        timer: Timer? = nil,
        player: PlayerModel? = nil
    ) {
        self.isLoadingVideo = isLoadingVideo
        self.isPlaying = isPlaying
        self.presentingControls = presentingControls
        self.presentingControlsOverlay = presentingControlsOverlay
        self.timer = timer
        self.player = player
    }

    func handlePresentationChange() {
        if presentingControls {
            DispatchQueue.main.async { [weak self] in
                self?.player?.backend.startControlsUpdates()
                self?.resetTimer()
            }
        } else {
            player?.backend.stopControlsUpdates()
            timer?.invalidate()
            timer = nil
        }
    }

    func show() {
        guard !(player?.currentItem.isNil ?? true) else {
            return
        }

        guard !presentingControls else {
            return
        }

        player.backend.updateControls()
        withAnimation(PlayerControls.animation) {
            presentingControls = true
        }
    }

    func hide() {
        guard let player = player,
              !player.musicMode
        else {
            return
        }

        player.backend.stopControlsUpdates()

        guard !player.currentItem.isNil else {
            return
        }

        guard presentingControls else {
            return
        }
        withAnimation(PlayerControls.animation) {
            presentingControls = false
        }
    }

    func toggle() {
        presentingControls ? hide() : show()
    }

    func resetTimer() {
        #if os(tvOS)
            if !presentingControls {
                show()
            }
        #endif

        removeTimer()

        guard let player = player, !player.musicMode else {
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            withAnimation(PlayerControls.animation) { [weak self] in
                self?.presentingControls = false
                self?.player.backend.stopControlsUpdates()
            }
        }
    }

    func startPiP(startImmediately: Bool = true) {
        if player.activeBackend == .mpv {
            player.avPlayerBackend.switchToMPVOnPipClose = true
        }

        #if !os(macOS)
            player.exitFullScreen()
        #endif

        if player.activeBackend != PlayerBackendType.appleAVPlayer {
            player.saveTime { [weak player] in
                player?.changeActiveBackend(from: .mpv, to: .appleAVPlayer)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak player] in
            player?.avPlayerBackend.startPictureInPictureOnPlay = true
            if startImmediately {
                player?.pipController?.startPictureInPicture()
            }
        }
    }

    func removeTimer() {
        timer?.invalidate()
        timer = nil
    }

    func update() {
        player?.backend.updateControls()
    }
}
