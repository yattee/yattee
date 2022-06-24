import Foundation
import SwiftUI

struct VideoDetailsPaddingModifier: ViewModifier {
    static var defaultAdditionalDetailsPadding = 0.0

    let geometry: GeometryProxy
    let aspectRatio: Double?
    let minimumHeightLeft: Double
    let additionalPadding: Double
    let fullScreen: Bool

    init(
        geometry: GeometryProxy,
        aspectRatio: Double? = nil,
        minimumHeightLeft: Double? = nil,
        additionalPadding: Double? = nil,
        fullScreen: Bool = false
    ) {
        self.geometry = geometry
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
        [geometry.size.width / usedAspectRatio, geometry.size.height - minimumHeightLeft].min()!
    }

    var topPadding: Double {
        fullScreen ? 0 : (playerHeight + additionalPadding)
    }

    func body(content: Content) -> some View {
        content
            .padding(.top, topPadding)
    }
}
