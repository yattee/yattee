import Defaults
import SwiftUI

struct BrowsingSettings: View {
    @Default(.channelOnThumbnail) private var channelOnThumbnail
    @Default(.timeOnThumbnail) private var timeOnThumbnail
    #if os(iOS)
        @Default(.tabNavigationSection) private var tabNavigationSection
    #endif

    var body: some View {
        Section(header: SettingsHeader(text: "Browsing"), footer: footer) {
            Toggle("Display channel names on thumbnails", isOn: $channelOnThumbnail)
            Toggle("Display video length on thumbnails", isOn: $timeOnThumbnail)

            #if os(iOS)
                preferredTabPicker
            #endif
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

        #if os(macOS)
            Spacer()
        #endif
    }

    var footer: some View {
        #if os(iOS)
            Text("This tab will be displayed when there is no space to display all tabs")
        #else
            EmptyView()
        #endif
    }

    #if os(iOS)
        var preferredTabPicker: some View {
            Picker("Preferred tab", selection: $tabNavigationSection) {
                Text("Trending").tag(TabNavigationSectionSetting.trending)
                Text("Popular").tag(TabNavigationSectionSetting.popular)
            }
        }
    #endif
}

struct BrowsingSettings_Previews: PreviewProvider {
    static var previews: some View {
        BrowsingSettings()
            .injectFixtureEnvironmentObjects()
    }
}
