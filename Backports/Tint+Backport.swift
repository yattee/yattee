import SwiftUI

extension Backport where Content: View {
    @ViewBuilder func tint(_ color: Color?) -> some View {
        // swiftlint:disable:next deployment_target
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            content.tint(color)
        } else {
            content.foregroundColor(color)
        }
    }
}
