import SwiftUI

extension Backport where Content: View {
    @ViewBuilder func tint(_ color: Color?) -> some View {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, *) {
            content.tint(color)
        } else {
            content.foregroundColor(color)
        }
    }
}
