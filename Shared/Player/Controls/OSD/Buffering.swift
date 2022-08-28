import Defaults
import Foundation
import SwiftUI

struct Buffering: View {
    var reason = "Buffering stream..."
    var state: String?

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    @EnvironmentObject<PlayerModel> private var player

    @Default(.playerControlsLayout) private var regularPlayerControlsLayout
    @Default(.fullScreenPlayerControlsLayout) private var fullScreenPlayerControlsLayout

    var playerControlsLayout: PlayerControlsLayout {
        fullScreenLayout ? fullScreenPlayerControlsLayout : regularPlayerControlsLayout
    }

    var fullScreenLayout: Bool {
        #if os(iOS)
            player.playingFullScreen || verticalSizeClass == .compact
        #else
            player.playingFullScreen
        #endif
    }

    var body: some View {
        VStack(spacing: 2) {
            ProgressView()
            #if os(macOS)
                .scaleEffect(0.4)
            #else
                .scaleEffect(0.7)
            #endif
                .frame(maxHeight: 14)
                .progressViewStyle(.circular)

            Text(reason)
                .font(.system(size: playerControlsLayout.timeFontSize))
            if let state = state {
                Text(state)
                    .font(.system(size: playerControlsLayout.bufferingStateFontSize).monospacedDigit())
            }
        }
        .padding(8)
        .modifier(ControlBackgroundModifier())
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .foregroundColor(.secondary)
    }
}

struct Buffering_Previews: PreviewProvider {
    static var previews: some View {
        Buffering(state: "100% (2.95s)")
    }
}
