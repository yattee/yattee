import Foundation
import SwiftUI

struct VideoDetailsPaddingModifier: ViewModifier {
    static var defaultAdditionalDetailsPadding = 0.0

    let playerSize: CGSize
    let aspectRatio: Double?
    let minimumHeightLeft: Double
    let additionalPadding: Double
    let fullScreen: Bool

    init(
        playerSize: CGSize,
        aspectRatio: Double? = nil,
        minimumHeightLeft: Double? = nil,
        additionalPadding: Double? = nil,
        fullScreen: Bool = false
    ) {
        self.playerSize = playerSize
        self.aspectRatio = aspectRatio ?? VideoPlayerView.defaultAspectRatio
        self.minimumHeightLeft = minimumHeightLeft ?? VideoPlayerView.defaultMinimumHeightLeft
        self.additionalPadding = additionalPadding ?? Self.defaultAdditionalDetailsPadding
        self.fullScreen = fullScreen
    }

    var usedAspectRatio: Double {
        guard aspectRatio != nil else {
            return VideoPlayerView.defaultAspectRatio
        }

        return [aspectRatio!, VideoPlayerView.defaultAspectRatio].min()!
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
