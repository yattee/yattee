import SwiftUI

extension Backport where Content: View {
    @ViewBuilder func toolbarBackground(_ color: Color) -> some View {
        // swiftlint:disable:next deployment_target
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            content
                .toolbarBackground(color, for: .navigationBar)
        } else {
            content
        }
    }

    @ViewBuilder func toolbarBackgroundVisibility(_ visible: Bool) -> some View {
        // swiftlint:disable:next deployment_target
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            content
                .toolbarBackground(visible ? .visible : .hidden, for: .navigationBar)
        } else {
            content
        }
    }
}
