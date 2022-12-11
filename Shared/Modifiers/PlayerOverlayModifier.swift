import Foundation
import SwiftUI

struct PlayerOverlayModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
        #if !os(tvOS)
        .overlay(ControlsBar(fullScreen: .constant(false)), alignment: .bottom)
        #endif
    }
}
