import Foundation
import SwiftUI

struct VideoPlayerSizeModifier: ViewModifier {
    let geometry: GeometryProxy
    let aspectRatio: Double?
    let fullScreen: Bool
    var detailsHiddenInFullScreen = true

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    init(
        geometry: GeometryProxy,
        aspectRatio: Double? = nil,
        fullScreen: Bool = false,
        detailsHiddenInFullScreen: Bool = false
    ) {
        self.geometry = geometry
        self.aspectRatio = aspectRatio ?? VideoPlayerView.defaultAspectRatio
        self.fullScreen = fullScreen
        self.detailsHiddenInFullScreen = detailsHiddenInFullScreen
    }

    func body(content: Content) -> some View {
        content
            .frame(width: geometry.size.width)
            .frame(maxHeight: maxHeight)
            .aspectRatio(ratio, contentMode: usedAspectRatioContentMode)
    }

    var ratio: CGFloat? { // swiftlint:disable:this no_cgfloat
        fullScreen ? detailsHiddenInFullScreen ? nil : usedAspectRatio : usedAspectRatio
    }

    var usedAspectRatio: Double {
        guard let aspectRatio, aspectRatio > 0 else {
            return VideoPlayerView.defaultAspectRatio
        }

        return aspectRatio
    }

    var usedAspectRatioContentMode: ContentMode {
        #if os(tvOS)
            .fit
        #else
            fullScreen ? .fill : .fit
        #endif
    }

    var maxHeight: Double {
        guard !fullScreen else {
            if detailsHiddenInFullScreen {
                return geometry.size.height
            }

            return geometry.size.width / usedAspectRatio
        }

        return max(geometry.size.height - VideoPlayerView.defaultMinimumHeightLeft, 0)
    }
}
