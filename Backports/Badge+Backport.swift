import SwiftUI

extension Backport where Content: View {
    @ViewBuilder func badge(_ count: Text?) -> some View {
        #if os(tvOS)
            content
        #else
            // swiftlint:disable:next deployment_target
            if #available(iOS 15.0, macOS 12.0, *) {
                content.badge(count)
            } else {
                content
            }
        #endif
    }
}
