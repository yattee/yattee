import Defaults
import SwiftUI

struct AppleAVPlayerView: NSViewRepresentable {
    @EnvironmentObject<PlayerModel> private var player

    func makeNSView(context _: Context) -> some NSView {
        let playerLayerView = PlayerLayerView(frame: .zero)

        playerLayerView.player = player

        return playerLayerView
    }

    func updateNSView(_: NSViewType, context _: Context) {}
}
