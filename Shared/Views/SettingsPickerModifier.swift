import Foundation
import SwiftUI

struct SettingsPickerModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(tvOS)
        content
            .pickerStyle(.inline)
            .onAppear {
                // Force refresh to apply button style to picker options
            }
        #elseif os(iOS)
        content
            .pickerStyle(.automatic)
        #else
        content
            .labelsHidden()
        #endif
    }
}

#if os(tvOS)
// Extension to help remove picker row backgrounds
extension View {
    func pickerRowStyle() -> some View {
        self.buttonStyle(.plain)
            .listRowBackground(Color.clear)
    }
}
#endif
