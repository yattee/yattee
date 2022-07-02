import Defaults
import SwiftUI

struct AdvancedSettings: View {
    @Default(.instancesManifest) private var instancesManifest
    @Default(.showMPVPlaybackStats) private var showMPVPlaybackStats
    @Default(.mpvCacheSecs) private var mpvCacheSecs
    @Default(.mpvCachePauseWait) private var mpvCachePauseWait

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
        Section(header: SettingsHeader(text: "MPV"), footer: mpvFooter) {
            showMPVPlaybackStatsToggle

            HStack {
                Text("cache-secs")
                #if os(macOS)
                    .frame(minWidth: 120, alignment: .leading)
                #endif
                TextField("cache-secs", text: $mpvCacheSecs)
            }

            HStack {
                Text("cache-pause-wait")
                #if os(macOS)
                    .frame(minWidth: 120, alignment: .leading)
                #endif
                TextField("cache-pause-wait", text: $mpvCachePauseWait)
            }
        }
        .multilineTextAlignment(.trailing)

        Section(header: manifestHeader) {
            TextField("URL", text: $instancesManifest)
            #if !os(macOS)
                .keyboardType(.webSearch)
            #endif
                .disableAutocorrection(true)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder var mpvFooter: some View {
        VStack(alignment: .leading) {
            Text("Restart the app to apply the settings above.")
            HStack(spacing: 2) {
                Text("More info can be found in")
                Link("MPV Documentation", destination: URL(string: "https://mpv.io/manual/master")!)
            }
        }
        .foregroundColor(.secondary)
    }

    var manifestHeader: some View {
        SettingsHeader(text: "Public Manifest")
    }

    var showMPVPlaybackStatsToggle: some View {
        Toggle("Show playback statistics", isOn: $showMPVPlaybackStats)
    }
}

struct AdvancedSettings_Previews: PreviewProvider {
    static var previews: some View {
        AdvancedSettings()
    }
}
