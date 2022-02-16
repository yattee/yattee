import Foundation
import SwiftUI

struct VideoPlayerSizeModifier: ViewModifier {
    let geometry: GeometryProxy
    let aspectRatio: Double?
    let minimumHeightLeft: Double
    let fullScreen: Bool

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    init(
        geometry: GeometryProxy,
        aspectRatio: Double? = nil,
        minimumHeightLeft: Double? = nil,
        fullScreen: Bool = false
    ) {
        self.geometry = geometry
        self.aspectRatio = aspectRatio ?? VideoPlayerView.defaultAspectRatio
        self.minimumHeightLeft = minimumHeightLeft ?? VideoPlayerView.defaultMinimumHeightLeft
        self.fullScreen = fullScreen
    }

    func body(content: Content) -> some View {
        content
            .frame(maxHeight: fullScreen ? .infinity : maxHeight)
            .aspectRatio(usedAspectRatio, contentMode: .fit)
    }

    var usedAspectRatio: Double {
        guard aspectRatio != nil else {
            return VideoPlayerView.defaultAspectRatio
        }

        let ratio = [aspectRatio!, VideoPlayerView.defaultAspectRatio].min()!
        let viewRatio = geometry.size.width / geometry.size.height

        #if os(iOS)
            return verticalSizeClass == .regular ? ratio : viewRatio
        #else
            return ratio
        #endif
    }

    var usedAspectRatioContentMode: ContentMode {
        #if os(iOS)
            !fullScreen ? .fit : .fill
        #else
                .fit
        #endif
    }

    var maxHeight: Double {
        #if os(iOS)
            let height = verticalSizeClass == .regular ? geometry.size.height - minimumHeightLeft : .infinity
        #else
            let height = geometry.size.height - minimumHeightLeft
        #endif

        return [height, 0].max()!
    }
}
