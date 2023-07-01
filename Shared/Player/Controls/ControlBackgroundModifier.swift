import Foundation
import SwiftUI

struct ControlBackgroundModifier: ViewModifier {
    var enabled = true
    var edgesIgnoringSafeArea = Edge.Set()

    func body(content: Content) -> some View {
        if enabled {
            content
                .background(.thinMaterial)
        } else {
            content
        }
    }
}
