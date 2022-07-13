import AVKit
import Defaults
import SwiftUI

struct AppleAVPlayerView: UIViewRepresentable {
    @EnvironmentObject<PlayerModel> private var player

    func makeUIView(context _: Context) -> some UIView {
        player.playerLayerView = PlayerLayerView(frame: .zero)
        return player.playerLayerView
    }

    func updateUIView(_: UIViewType, context _: Context) {}
}
