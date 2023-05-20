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
            .frame(maxWidth: geometry.size.width)
            .frame(maxHeight: maxHeight)

        #if !os(macOS)
            .aspectRatio(ratio, contentMode: usedAspectRatioContentMode)
        #endif
    }

    var ratio: CGFloat? {
        fullScreen ? detailsHiddenInFullScreen ? nil : usedAspectRatio : usedAspectRatio
    }

    var usedAspectRatio: Double {
        guard let aspectRatio, aspectRatio > 0 else {
            return VideoPlayerView.defaultAspectRatio
        }

        return aspectRatio
    }

    var usedAspectRatioContentMode: ContentMode {
        #if os(iOS)
            fullScreen ? .fill : .fit
        #else
            .fit
        #endif
    }

    var maxHeight: Double {
        guard !fullScreen else {
            if detailsHiddenInFullScreen {
                return geometry.size.height
            } else {
                return geometry.size.width / usedAspectRatio
            }
        }

        return max(geometry.size.height - VideoPlayerView.defaultMinimumHeightLeft, 0)
    }
}
