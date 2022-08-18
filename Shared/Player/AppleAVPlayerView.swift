import AVKit
import Defaults
import SwiftUI

struct AppleAVPlayerView: UIViewRepresentable {
    @EnvironmentObject<PlayerModel> private var player

    func makeUIView(context _: Context) -> some UIView {
        let playerLayerView = PlayerLayerView(frame: .zero)
        playerLayerView.player = player
        return playerLayerView
    }

    func updateUIView(_: UIViewType, context _: Context) {}
}
