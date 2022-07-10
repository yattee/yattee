import Foundation
import SwiftUI

struct VideoDetailsPaddingModifier: ViewModifier {
    static var defaultAdditionalDetailsPadding = 0.0

    let playerSize: CGSize
    let minimumHeightLeft: Double
    let additionalPadding: Double
    let fullScreen: Bool

    init(
        playerSize: CGSize,
        minimumHeightLeft: Double? = nil,
        additionalPadding: Double? = nil,
        fullScreen: Bool = false
    ) {
        self.playerSize = playerSize
        self.minimumHeightLeft = minimumHeightLeft ?? VideoPlayerView.defaultMinimumHeightLeft
        self.additionalPadding = additionalPadding ?? Self.defaultAdditionalDetailsPadding
        self.fullScreen = fullScreen
    }

    var playerHeight: Double {
        playerSize.height
    }

    var topPadding: Double {
        fullScreen ? 0 : (playerHeight + additionalPadding)
    }

    func body(content: Content) -> some View {
        content
            .padding(.top, topPadding)
    }
}
