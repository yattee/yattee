import AVFoundation
import Foundation
import UIKit

final class PlayerLayerView: UIView {
    var playerLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)

        layer.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
