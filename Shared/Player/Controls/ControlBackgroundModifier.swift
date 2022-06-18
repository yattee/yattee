import Foundation
import SwiftUI

struct ControlBackgroundModifier: ViewModifier {
    var enabled = true
    var edgesIgnoringSafeArea = Edge.Set()

    func body(content: Content) -> some View {
        if enabled {
            content
            #if os(macOS)
            .background(VisualEffectBlur(material: .hudWindow))
            #elseif os(iOS)
            .background(VisualEffectBlur(blurStyle: .systemThinMaterial).edgesIgnoringSafeArea(edgesIgnoringSafeArea))
            #else
            .background(.thinMaterial)
            #endif
        } else {
            content
        }
    }
}
