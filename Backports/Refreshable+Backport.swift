import SwiftUI

extension Backport where Content: View {
    @ViewBuilder func refreshable(action: @Sendable @escaping () async -> Void) -> some View {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, *) {
            content.refreshable(action: action)
        } else {
            content
        }
    }
}
