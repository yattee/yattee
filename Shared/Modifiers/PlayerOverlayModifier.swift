import Defaults
import Foundation
import SwiftUI

struct PlayerOverlayModifier: ViewModifier {
    @ObservedObject private var player = PlayerModel.shared
    @State private var expansionState = ControlsBar.ExpansionState.mini

    @Environment(\.navigationStyle) private var navigationStyle

    @Default(.playerButtonShowsControlButtonsWhenMinimized) private var controlsWhenMinimized
    @Default(.playerButtonIsExpanded) private var playerButtonIsExpanded
    @Default(.playerBarMaxWidth) private var playerBarMaxWidth

    func body(content: Content) -> some View {
        content
        #if !os(tvOS)
        .overlay(overlay, alignment: .bottomTrailing)
        #endif
    }

    @ViewBuilder var overlay: some View {
        Group {
            ControlsBar(fullScreen: .constant(false), expansionState: $expansionState, playerBar: true)
                .offset(x: expansionState == .mini && !controlsWhenMinimized ? 10 : 0, y: 0)
                .frame(maxWidth: maxWidth, alignment: .trailing)
                .onAppear {
                    if playerButtonIsExpanded {
                        expansionState = .full
                    }
                }
                .animation(.easeIn, value: player.videoForDisplay)
                .opacity(opacity)
        }
    }

    var opacity: Double {
        guard !player.closing else { return 0 }

        return player.videoForDisplay == nil ? 0 : 1
    }

    var maxWidth: Double {
        playerBarMaxWidth == "0" ? .infinity : (Double(playerBarMaxWidth) ?? 600)
    }
}

struct PlayerOverlayModifier_Previews: PreviewProvider {
    static var previews: some View {
        HStack {}
            .frame(maxWidth: .infinity, maxHeight: 100)
            .modifier(PlayerOverlayModifier())
    }
}
