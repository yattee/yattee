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

        override func makeBackingLayer() -> CALayer {
            player.avPlayerBackend.playerLayer
        }

        override init(frame frameRect: CGRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }
    }
#else
    final class PlayerLayerView: UIView {
        var player: PlayerModel { .shared }

        private var layerAdded = false

        // swiftlint:disable:next unneeded_override
        override init(frame: CGRect) {
            super.init(frame: frame)
        }

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
