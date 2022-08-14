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
            .frame(width: geometry.size.width)
            .frame(maxHeight: maxHeight)
        #if !os(macOS)
            .aspectRatio(fullScreen ? nil : usedAspectRatio, contentMode: usedAspectRatioContentMode)
        #endif
    }

    var usedAspectRatio: Double {
        guard let aspectRatio = aspectRatio, aspectRatio > 0, aspectRatio < VideoPlayerView.defaultAspectRatio else {
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
            return .infinity
        }

        #if os(iOS)
            let height = verticalSizeClass == .regular ? geometry.size.height - minimumHeightLeft : .infinity
        #else
            let height = geometry.size.height - minimumHeightLeft
        #endif

        return [height, 0].max()!
    }
}
