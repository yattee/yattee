import Defaults
import SwiftUI

struct AdvancedSettings: View {
    @Default(.instancesManifest) private var instancesManifest
    @Default(.showMPVPlaybackStats) private var showMPVPlaybackStats

    var body: some View {
        VStack(alignment: .leading) {
            #if os(macOS)
                advancedSettings
                Spacer()
            #else
                List {
                    advancedSettings
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
            #endif
        }
        #if os(tvOS)
        .frame(maxWidth: 1000)
        #endif
        .navigationTitle("Advanced")
    }

    @ViewBuilder var advancedSettings: some View {
        Section(header: manifestHeader, footer: manifestFooter) {
            TextField("URL", text: $instancesManifest)
        }
        .padding(.bottom, 4)

        Section(header: SettingsHeader(text: "Debugging")) {
            showMPVPlaybackStatsToggle
        }
    }

    var manifestHeader: some View {
        SettingsHeader(text: "Public Manifest")
    }

    var manifestFooter: some View {
        Text("You can create your own locations manifest and set its URL here to replace the built-in one")
            .foregroundColor(.secondary)
    }

    var showMPVPlaybackStatsToggle: some View {
        Toggle("Show MPV playback statistics", isOn: $showMPVPlaybackStats)
    }
}

struct AdvancedSettings_Previews: PreviewProvider {
    static var previews: some View {
        AdvancedSettings()
    }
}
