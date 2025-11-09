import SwiftUI

extension Backport where Content: View {
    @ViewBuilder func persistentSystemOverlays(_ visible: Bool) -> some View {
        // swiftlint:disable:next deployment_target
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            content.persistentSystemOverlays(visible ? .visible : .hidden)
        } else {
            content
        }
    }
}
