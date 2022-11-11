import SwiftUI

struct OpeningStream: View {
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<NetworkStateModel> private var model

    var body: some View {
        Buffering(reason: reason, state: state)
            .opacity(visible ? 1 : 0)
    }

    var visible: Bool {
        (!player.currentItem.isNil && !player.videoBeingOpened.isNil) || (player.isLoadingVideo && !model.pausedForCache && !player.isSeeking)
    }

    var reason: String {
        guard player.videoBeingOpened == nil else {
            return "Loading streams...".localized()
        }

        if player.musicMode {
            return "Opening audio stream...".localized()
        }

        if let selection = player.streamSelection {
            if selection.isLocal {
                return "Opening file..."
            } else {
                return String(format: "Opening %@ stream...".localized(), selection.shortQuality)
            }
        }

        return "Loading streams...".localized()
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
