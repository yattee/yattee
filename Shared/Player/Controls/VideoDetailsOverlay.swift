import Defaults
import SwiftUI

struct VideoDetailsOverlay: View {
    @ObservedObject private var controls = PlayerControlsModel.shared

    var body: some View {
        VideoDetails(video: controls.player.videoForDisplay, fullScreen: fullScreenBinding, sidebarQueue: .constant(false))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(.leading, overlayLeadingPadding)
            .id(controls.player.currentVideo?.cacheKey)
    }

    var fullScreenBinding: Binding<Bool> {
        .init(get: {
            controls.presentingDetailsOverlay
        }, set: { newValue in
            controls.presentingDetailsOverlay = newValue
        })
    }

    #if os(iOS)
        private var overlayLeadingPadding: CGFloat {
            // On iPad in non-fullscreen mode, add left padding for system controls
            if Constants.isIPad && !Constants.isWindowFullscreen {
                return Constants.iPadSystemControlsWidth + 15
            }
            return 0
        }
    #else
        private var overlayLeadingPadding: CGFloat {
            return 0
        }
    #endif
}

struct VideoDetailsOverlay_Previews: PreviewProvider {
    static var previews: some View {
        VideoDetailsOverlay()
            .injectFixtureEnvironmentObjects()
    }
}
