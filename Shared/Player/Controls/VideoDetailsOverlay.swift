import Defaults
import SwiftUI

struct VideoDetailsOverlay: View {
    @ObservedObject private var controls = PlayerControlsModel.shared

    @State private var detailsPage = VideoDetails.DetailsPage.info

    var body: some View {
        VideoDetails(video: PlayerModel.shared.currentVideo, page: $detailsPage, sidebarQueue: .constant(false), fullScreen: fullScreenBinding)
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
