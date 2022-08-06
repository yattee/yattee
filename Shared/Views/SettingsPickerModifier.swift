import Foundation
import SwiftUI

struct SettingsPickerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
        #if os(tvOS)
        .pickerStyle(.inline)
        #endif
        #if os(iOS)
        .pickerStyle(.automatic)
        #else
        .labelsHidden()
        #endif
    }
}
