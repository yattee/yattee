import SwiftUI

extension Backport where Content: View {
    @ViewBuilder func toolbarColorScheme(_ colorScheme: ColorScheme) -> some View {
        if #available(iOS 16, *) {
            content
                .toolbarColorScheme(colorScheme, for: .navigationBar)
        } else {
            content
        }
    }
}
