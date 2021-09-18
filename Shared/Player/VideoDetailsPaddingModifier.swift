import Foundation
import SwiftUI

struct VideoDetailsPaddingModifier: ViewModifier {
    let geometry: GeometryProxy
    let aspectRatio: Double?
    let minimumHeightLeft: Double
    let additionalPadding: Double

    init(
        geometry: GeometryProxy,
        aspectRatio: Double? = nil,
        minimumHeightLeft: Double? = nil,
        additionalPadding: Double = 35.00
    ) {
        self.geometry = geometry
        self.aspectRatio = aspectRatio ?? VideoPlayerView.defaultAspectRatio
        self.minimumHeightLeft = minimumHeightLeft ?? VideoPlayerView.defaultMinimumHeightLeft
        self.additionalPadding = additionalPadding
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
        playerHeight + additionalPadding
    }

    func body(content: Content) -> some View {
        content
            .padding(.top, topPadding)
    }
}
