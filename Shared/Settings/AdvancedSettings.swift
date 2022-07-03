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
                    .frame(minWidth: 140, alignment: .leading)
                TextField("cache-secs", text: $mpvCacheSecs)
            }
            .multilineTextAlignment(.trailing)

            HStack {
                Text("cache-pause-wait")
                    .frame(minWidth: 140, alignment: .leading)
                TextField("cache-pause-wait", text: $mpvCachePauseWait)
            }
            .multilineTextAlignment(.trailing)
        }

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
        let url = "https://mpv.io/manual/master"

        VStack(alignment: .leading) {
            Text("Restart the app to apply the settings above.")
            VStack(alignment: .leading, spacing: 2) {
                #if os(tvOS)
                    Text("More info can be found in MPV Documentation:")
                    Text(url)
                #else
                    Text("More info can be found in:")
                    Link("MPV Documentation", destination: URL(string: url)!)
                    #if os(macOS)
                        .onHover(perform: onHover(_:))
                    #endif
                #endif
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

    #if os(macOS)
        private func onHover(_ inside: Bool) {
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    #endif
}

struct AdvancedSettings_Previews: PreviewProvider {
    static var previews: some View {
        AdvancedSettings()
    }
}
