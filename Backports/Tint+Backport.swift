import SwiftUI

extension Backport where Content: View {
    @ViewBuilder func tint(_ color: Color?) -> some View {
        content.tint(color)
    }
}
