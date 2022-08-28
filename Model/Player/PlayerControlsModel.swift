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
        private(set) var reporter = PassthroughSubject<String, Never>()
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
        guard let player = player else { return }
        if presentingControls {
            DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
                player.backend.startControlsUpdates()
                self?.resetTimer()
            }
        } else {
            if !player.musicMode {
                DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
                    player.backend.stopControlsUpdates()
                    self?.removeTimer()
                }
            } else {
                DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
                    self?.presentingControls = true
                }
            }
        }
    }

    func handleSettingsOverlayPresentationChange() {
        player?.backend.setNeedsNetworkStateUpdates(presentingControlsOverlay && Defaults[.showMPVPlaybackStats])
    }

    func handleDetailsOverlayPresentationChange() {}

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
