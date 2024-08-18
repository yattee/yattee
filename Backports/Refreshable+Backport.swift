import SwiftUI

extension Backport where Content: View {
    @ViewBuilder func refreshable(action: @Sendable @escaping () async -> Void) -> some View {
        content.refreshable(action: action)
    }
}
