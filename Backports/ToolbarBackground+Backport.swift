import SwiftUI

extension Backport where Content: View {
    @ViewBuilder func toolbarBackground(_ color: Color) -> some View {
        if #available(iOS 16, *) {
            content
                .toolbarBackground(color, for: .navigationBar)
        } else {
            content
        }
    }

    @ViewBuilder func toolbarBackgroundVisibility(_ visible: Bool) -> some View {
        if #available(iOS 16, *) {
            content
                .toolbarBackground(visible ? .visible : .hidden, for: .navigationBar)
        } else {
            content
        }
    }
}
