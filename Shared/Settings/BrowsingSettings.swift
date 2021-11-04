import Defaults
import SwiftUI

struct BrowsingSettings: View {
    @Default(.channelOnThumbnail) private var channelOnThumbnail
    @Default(.timeOnThumbnail) private var timeOnThumbnail

    var body: some View {
        Section(header: SettingsHeader(text: "Thumbnails")) {
            Toggle("Display channel names on thumbnails", isOn: $channelOnThumbnail)
            Toggle("Display video length on thumbnails", isOn: $timeOnThumbnail)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

        #if os(macOS)
            Spacer()
        #endif
    }
}

struct BrowsingSettings_Previews: PreviewProvider {
    static var previews: some View {
        BrowsingSettings()
            .injectFixtureEnvironmentObjects()
    }
}
