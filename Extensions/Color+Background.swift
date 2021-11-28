import SwiftUI

extension Color {
    #if os(macOS)
        static let background = Color(NSColor.windowBackgroundColor)
        static let secondaryBackground = Color(NSColor.underPageBackgroundColor)
        static let tertiaryBackground = Color(NSColor.controlBackgroundColor)
    #elseif os(iOS)
        static let background = Color(UIColor.systemBackground)
        static let secondaryBackground = Color(UIColor.secondarySystemBackground)
        static let tertiaryBackground = Color(UIColor.tertiarySystemBackground)
    #else
        static let background = Color.black
        static let secondaryBackground = Color.black
        static let tertiaryBackground = Color.black
    #endif
}
