import Defaults
import SwiftUI

struct AppleAVPlayerView: NSViewRepresentable {
    func makeNSView(context _: Context) -> some NSView {
        PlayerLayerView(frame: .zero)
    }

    func updateNSView(_: NSViewType, context _: Context) {}
}
