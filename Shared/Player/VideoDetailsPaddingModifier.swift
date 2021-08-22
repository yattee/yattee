import Foundation
import SwiftUI

struct VideoDetailsPaddingModifier: ViewModifier {
    let geometry: GeometryProxy
    let aspectRatio: CGFloat?
    let minimumHeightLeft: CGFloat
    let additionalPadding: CGFloat

    init(
        geometry: GeometryProxy,
        aspectRatio: CGFloat? = nil,
        minimumHeightLeft: CGFloat? = nil,
        additionalPadding: CGFloat = 35.00
    ) {
        self.geometry = geometry
        self.aspectRatio = aspectRatio ?? VideoPlayerView.defaultAspectRatio
        self.minimumHeightLeft = minimumHeightLeft ?? VideoPlayerView.defaultMinimumHeightLeft
        self.additionalPadding = additionalPadding
    }

    var usedAspectRatio: CGFloat {
        guard aspectRatio != nil else {
            return VideoPlayerView.defaultAspectRatio
        }

        return [aspectRatio!, VideoPlayerView.defaultAspectRatio].min()!
    }

    var playerHeight: CGFloat {
        [geometry.size.width / usedAspectRatio, geometry.size.height - minimumHeightLeft].min()!
    }

    var topPadding: CGFloat {
        playerHeight + additionalPadding
    }

    func body(content: Content) -> some View {
        content
            .padding(.top, topPadding)
    }
}
