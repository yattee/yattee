import SwiftUI

extension Color {
    #if os(macOS)
        static let background = Color(NSColor.windowBackgroundColor)
        static let secondaryBackground = Color(NSColor.controlBackgroundColor)
    #elseif os(iOS)
        static let background = Color(UIColor.systemBackground)
        static let secondaryBackground = Color(UIColor.secondarySystemBackground)
    #else
        static func background(scheme: ColorScheme) -> Color {
            scheme == .dark ? .black : .init(white: 0.8)
        }
    #endif
}
