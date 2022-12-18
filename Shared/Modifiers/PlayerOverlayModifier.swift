import Defaults
import Foundation
import SwiftUI

struct PlayerOverlayModifier: ViewModifier {
    @ObservedObject private var player = PlayerModel.shared
    @State private var expansionState = ControlsBar.ExpansionState.mini

    @Environment(\.navigationStyle) private var navigationStyle

    @Default(.playerButtonShowsControlButtonsWhenMinimized) private var controlsWhenMinimized

    func body(content: Content) -> some View {
        content
        #if !os(tvOS)
        .overlay(overlay, alignment: .bottomTrailing)
        #endif
    }

    @ViewBuilder var overlay: some View {
        Group {
            if player.videoForDisplay != nil {
                ControlsBar(fullScreen: .constant(false), expansionState: $expansionState, playerBar: true)
                    .offset(x: expansionState == .mini && !controlsWhenMinimized ? 10 : 0, y: 0)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: player.currentItem)
    }
}

struct PlayerOverlayModifier_Previews: PreviewProvider {
    static var previews: some View {
        HStack {}
            .frame(maxWidth: .infinity, maxHeight: 100)
            .modifier(PlayerOverlayModifier())
    }
}
