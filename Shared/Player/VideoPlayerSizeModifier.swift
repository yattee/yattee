import Foundation
import SwiftUI

struct VideoPlayerSizeModifier: ViewModifier {
    let geometry: GeometryProxy!
    let aspectRatio: Double?
    let minimumHeightLeft: Double

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    init(
        geometry: GeometryProxy? = nil,
        aspectRatio: Double? = nil,
        minimumHeightLeft: Double? = nil
    ) {
        self.geometry = geometry
        self.aspectRatio = aspectRatio ?? VideoPlayerView.defaultAspectRatio
        self.minimumHeightLeft = minimumHeightLeft ?? VideoPlayerView.defaultMinimumHeightLeft
    }

    func body(content: Content) -> some View {
        // TODO: verify if optional GeometryProxy is still used
        if geometry != nil {
            content
                .frame(maxHeight: maxHeight)
                .aspectRatio(usedAspectRatio, contentMode: usedAspectRatioContentMode)
                .edgesIgnoringSafeArea(edgesIgnoringSafeArea)
        } else {
            content.edgesIgnoringSafeArea(edgesIgnoringSafeArea)
        }
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
            verticalSizeClass == .regular ? .fit : .fill
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

    var edgesIgnoringSafeArea: Edge.Set {
        let empty = Edge.Set()

        #if os(iOS)
            return verticalSizeClass == .compact ? .all : empty
        #else
            return empty
        #endif
    }
}
