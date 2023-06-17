import Combine
import CoreMedia
import Defaults
import Foundation
import SwiftUI

final class PlayerControlsModel: ObservableObject {
    static var shared = PlayerControlsModel()

    @Published var isLoadingVideo = false
    @Published var isPlaying = true
    @Published var presentingControls = false { didSet { handlePresentationChange() } }
    @Published var presentingDetailsOverlay = false { didSet { handleDetailsOverlayPresentationChange() } }
    var timer: Timer?

    #if os(tvOS)
        private(set) var reporter = PassthroughSubject<String, Never>() // swiftlint:disable:this private_subject
    #endif

    var player: PlayerModel! { .shared }
    private var controlsOverlayModel = ControlOverlaysModel.shared

    init(
        isLoadingVideo: Bool = false,
        isPlaying: Bool = true,
        presentingControls: Bool = false,
        presentingDetailsOverlay: Bool = false,
        timer: Timer? = nil
    ) {
        self.isLoadingVideo = isLoadingVideo
        self.isPlaying = isPlaying
        self.presentingControls = presentingControls
        self.presentingDetailsOverlay = presentingDetailsOverlay
        self.timer = timer
    }

    func handlePresentationChange() {
        guard let player else { return }
        if presentingControls {
            DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
                player.backend.startControlsUpdates()
                self?.resetTimer()
            }
        } else {
            #if os(macOS)
                NSCursor.setHiddenUntilMouseMoves(player.playingFullScreen)
            #endif
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
        player?.backend.setNeedsNetworkStateUpdates(controlsOverlayModel.presenting && Defaults[.showMPVPlaybackStats])
    }

    func handleDetailsOverlayPresentationChange() {}

    var presentingOverlays: Bool {
        presentingDetailsOverlay || controlsOverlayModel.presenting
    }

    func hideOverlays() {
        presentingDetailsOverlay = false
        controlsOverlayModel.hide()
    }

    func show() {
        guard !player.currentItem.isNil, !presentingControls else {
            return
        }

        player.backend.updateControls()
        withAnimation(PlayerControls.animation) {
            presentingControls = true
        }
    }

    func hide() {
        guard let player,
              !player.musicMode
        else {
            return
        }

        player.backend?.stopControlsUpdates()

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
        if presentingControls {
            hide()
        } else {
            show()
        }
    }

    func resetTimer() {
        removeTimer()

        guard let player, !player.musicMode else {
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
