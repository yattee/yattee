import SwiftUI

struct SettingsHeader: View {
    var text: String

    var body: some View {
        Text(text)
        #if os(macOS) || os(tvOS)
            .font(.title3)
            .foregroundColor(.secondary)
            .focusable(false)
        #endif
    }
}

struct SettingsHeader_Previews: PreviewProvider {
    static var previews: some View {
        SettingsHeader(text: "Header")
    }
}
