import Defaults
import SwiftUI

struct VideoDetailsOverlay: View {
    @EnvironmentObject<PlayerControlsModel> private var controls

    var body: some View {
        VideoDetails(sidebarQueue: false, fullScreen: fullScreenBinding)
            .modifier(ControlBackgroundModifier())
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
