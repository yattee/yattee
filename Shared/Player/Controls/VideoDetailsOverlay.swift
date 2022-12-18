import Defaults
import SwiftUI

struct VideoDetailsOverlay: View {
    @ObservedObject private var controls = PlayerControlsModel.shared

    var body: some View {
        VideoDetails(video: PlayerModel.shared.currentVideo, fullScreen: fullScreenBinding)
            .clipShape(RoundedRectangle(cornerRadius: 4))
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
