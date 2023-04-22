import Defaults
import SwiftUI

struct VideoDetailsOverlay: View {
    @ObservedObject private var controls = PlayerControlsModel.shared

    var body: some View {
        VideoDetails(video: controls.player.videoForDisplay, fullScreen: fullScreenBinding, sidebarQueue: .constant(false))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .id(controls.player.currentVideo?.cacheKey)
    }

    var fullScreenBinding: Binding<Bool> {
        .init(get: {
            controls.presentingDetailsOverlay
        }, set: { newValue in
            controls.presentingDetailsOverlay = newValue
        })
    }
}

struct VideoDetailsOverlay_Previews: PreviewProvider {
    static var previews: some View {
        VideoDetailsOverlay()
            .injectFixtureEnvironmentObjects()
    }
}
