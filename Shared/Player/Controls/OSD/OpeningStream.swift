import SwiftUI

struct OpeningStream: View {
    @ObservedObject private var player = PlayerModel.shared
    @ObservedObject private var model = NetworkStateModel.shared

    var body: some View {
        Buffering(reason: reason, state: state)
            .opacity(visible ? 1 : 0)
    }

    var visible: Bool {
        (!player.currentItem.isNil && !player.videoBeingOpened.isNil) ||
            (player.isLoadingVideo && !model.pausedForCache && !player.isSeeking) ||
            !player.hasStarted
    }

    var reason: String {
        guard player.videoBeingOpened == nil else {
            return "Loading streams…".localized()
        }

        if player.musicMode {
            return "Opening audio stream…".localized()
        }

        if let selection = player.streamSelection {
            if selection.isLocal {
                return "Opening file…".localized()
            }
            return String(format: "Opening %@ stream…".localized(), selection.shortQuality)
        }

        return "Loading streams…".localized()
    }

    var state: String? {
        player.videoBeingOpened.isNil ? model.bufferingStateText : nil
    }
}

struct OpeningStream_Previews: PreviewProvider {
    static var previews: some View {
        OpeningStream()
            .injectFixtureEnvironmentObjects()
    }
}
