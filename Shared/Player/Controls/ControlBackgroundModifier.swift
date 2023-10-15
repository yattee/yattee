import Foundation
import SwiftUI

struct ControlBackgroundModifier: ViewModifier {
    var enabled = true
    var edgesIgnoringSafeArea = Edge.Set()

    func body(content: Content) -> some View {
        if enabled {
            if #available(iOS 15, macOS 12, *) {
                content
                    .background(.thinMaterial)
            } else {
                content
                #if os(macOS)
                .background(VisualEffectBlur(material: .hudWindow))
                #elseif os(iOS)
                .background(VisualEffectBlur(blurStyle: .systemThinMaterial).edgesIgnoringSafeArea(edgesIgnoringSafeArea))
                #else
                .background(.thinMaterial)
                #endif
            }
        } else {
            content
        }
    }
}
