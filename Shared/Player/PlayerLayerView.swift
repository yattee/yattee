import AVFoundation
import Foundation
#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

#if os(macOS)
    final class PlayerLayerView: NSView {
        var player = PlayerModel.shared { didSet {
            wantsLayer = true
        }}

        override init(frame frameRect: CGRect) {
            super.init(frame: frameRect)
        }

        override func makeBackingLayer() -> CALayer {
            player.avPlayerBackend.playerLayer
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }
    }
#else
    final class PlayerLayerView: UIView {
        var player: PlayerModel { .shared }

        override init(frame: CGRect) {
            super.init(frame: frame)
        }

        private var layerAdded = false

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            if !layerAdded {
                layerAdded = true
                layer.addSublayer(player.avPlayerBackend.playerLayer)
            }
            player.avPlayerBackend.playerLayer.frame = bounds
            super.layoutSubviews()
        }
    }
#endif
