import SwiftUI

struct SettingsHeader: View {
    var text: String
    var secondary = false

    var body: some View {
        Group {
            #if os(iOS)
                if secondary {
                    EmptyView()
                } else {
                    Text(text.localized())
                }
            #else
                Text(text.localized())
            #endif
        }
        #if os(tvOS)
        .font(secondary ? .footnote : .title3)
        .foregroundColor(.secondary)
        .focusable(false)
        #endif
        #if os(macOS)
        .font(secondary ? .system(size: 13) : .system(size: 15))
        .foregroundColor(secondary ? Color.primary : .secondary)
        #endif
    }
}

struct SettingsHeader_Previews: PreviewProvider {
    static var previews: some View {
        SettingsHeader(text: "Header")
    }
}
