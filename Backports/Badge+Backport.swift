import SwiftUI

extension Backport where Content: View {
    @ViewBuilder func badge(_ count: Text?) -> some View {
        content
        #if !os(tvOS)
        .badge(count)
        #endif
    }
}
