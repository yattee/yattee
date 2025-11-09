import SwiftUI

extension Backport where Content: View {
    @ViewBuilder func toolbarColorScheme(_ colorScheme: ColorScheme) -> some View {
        // swiftlint:disable:next deployment_target
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            content
                .toolbarColorScheme(colorScheme, for: .navigationBar)
        } else {
            content
        }
    }
}
