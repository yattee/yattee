import SwiftUI

extension Backport where Content: View {
    @ViewBuilder func badge(_ count: Text?) -> some View {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, *) {
            content.badge(count)
        } else {
            content
        }
    }
}
