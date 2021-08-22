import Foundation
import SwiftUI

struct VideoPlayerSizeModifier: ViewModifier {
    let geometry: GeometryProxy
    let aspectRatio: CGFloat?
    let minimumHeightLeft: CGFloat

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    init(
        geometry: GeometryProxy,
        aspectRatio: CGFloat? = nil,
        minimumHeightLeft: CGFloat? = nil
    ) {
        self.geometry = geometry
        self.aspectRatio = aspectRatio ?? VideoPlayerView.defaultAspectRatio
        self.minimumHeightLeft = minimumHeightLeft ?? VideoPlayerView.defaultMinimumHeightLeft
    }

    func body(content: Content) -> some View {
        content
            .frame(maxHeight: maxHeight)
            .aspectRatio(usedAspectRatio, contentMode: usedAspectRatioContentMode)
            .edgesIgnoringSafeArea(edgesIgnoringSafeArea)
    }

    var usedAspectRatio: CGFloat {
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
            verticalSizeClass == .regular ? .fit : .fill
        #else
            .fit
        #endif
    }

    var maxHeight: CGFloat {
        #if os(iOS)
            verticalSizeClass == .regular ? geometry.size.height - minimumHeightLeft : .infinity
        #else
            geometry.size.height - minimumHeightLeft
        #endif
    }

    var edgesIgnoringSafeArea: Edge.Set {
        let empty = Edge.Set()

        #if os(iOS)
            return verticalSizeClass == .compact ? .all : empty
        #else
            return empty
        #endif
    }
}
