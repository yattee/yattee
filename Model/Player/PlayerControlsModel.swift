import Combine
import CoreMedia
import Defaults
import Foundation
import SwiftUI

final class PlayerControlsModel: ObservableObject {
    @Published var isLoadingVideo = false
    @Published var isPlaying = true
    @Published var presentingControls = false { didSet { handlePresentationChange() } }
    @Published var presentingControlsOverlay = false { didSet { handleSettingsOverlayPresentationChange() } }
    @Published var presentingDetailsOverlay = false { didSet { handleDetailsOverlayPresentationChange() } }
    var timer: Timer?

    #if os(tvOS)
        var reporter = PassthroughSubject<String, Never>()
    #endif

    var player: PlayerModel!

    init(
        isLoadingVideo: Bool = false,
        isPlaying: Bool = true,
        presentingControls: Bool = false,
        presentingControlsOverlay: Bool = false,
        presentingDetailsOverlay: Bool = false,
        timer: Timer? = nil,
        player: PlayerModel? = nil
    ) {
        self.isLoadingVideo = isLoadingVideo
        self.isPlaying = isPlaying
        self.presentingControls = presentingControls
        self.presentingControlsOverlay = presentingControlsOverlay
        self.presentingDetailsOverlay = presentingDetailsOverlay
        self.timer = timer
        self.player = player
    }

    func handlePresentationChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.presentingControls {
                self.player?.backend.startControlsUpdates()
                self.resetTimer()
            } else {
                self.player?.backend.stopControlsUpdates()
                self.timer?.invalidate()
                self.timer = nil
            }
        }
    }

    func handleSettingsOverlayPresentationChange() {
        player?.backend.setNeedsNetworkStateUpdates(presentingControlsOverlay && Defaults[.showMPVPlaybackStats])
        if presentingControlsOverlay {
            removeTimer()
        } else {
            resetTimer()
        }
    }

    func handleDetailsOverlayPresentationChange() {
        if presentingDetailsOverlay {
            removeTimer()
        } else {
            resetTimer()
        }
    }

    var presentingOverlays: Bool {
        presentingDetailsOverlay || presentingControlsOverlay
    }

    func hideOverlays() {
        presentingDetailsOverlay = false
        presentingControlsOverlay = false
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
