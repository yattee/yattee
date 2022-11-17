import Defaults
import Foundation
import SwiftUI

final class ControlOverlaysModel: ObservableObject {
    static let animation = Animation.easeInOut(duration: 0.2)
    static let shared = ControlOverlaysModel()
    @Published private(set) var presenting = false { didSet { handlePresentationChange() } }

    private lazy var controls = PlayerControlsModel.shared
    private lazy var player: PlayerModel! = PlayerModel.shared

    func toggle() {
        presenting.toggle()
        controls.objectWillChange.send()
    }

    func hide() {
        presenting = false
        controls.objectWillChange.send()
    }

    func show() {
        presenting = true
        controls.objectWillChange.send()
    }

    private func handlePresentationChange() {
        guard let player else { return }
        player.backend.setNeedsNetworkStateUpdates(presenting && Defaults[.showMPVPlaybackStats])
    }
}
