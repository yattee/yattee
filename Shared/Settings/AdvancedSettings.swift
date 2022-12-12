import Defaults
import SwiftUI

struct AdvancedSettings: View {
    @Default(.showMPVPlaybackStats) private var showMPVPlaybackStats
    @Default(.mpvCacheSecs) private var mpvCacheSecs
    @Default(.mpvCachePauseWait) private var mpvCachePauseWait
    @Default(.mpvEnableLogging) private var mpvEnableLogging
    @Default(.countryOfPublicInstances) private var countryOfPublicInstances
    @Default(.instances) private var instances

    @State private var countries = [String]()
    @State private var filesToShare = [MPVClient.logFile]
    @State private var presentingShareSheet = false

    private var settings = SettingsModel.shared

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
                .sheet(isPresented: $presentingShareSheet) {
                    ShareSheet(activityItems: filesToShare)
                        .id("logs-\(filesToShare.count)")
                }
                .listStyle(.insetGrouped)
                #endif
            #endif
        }
        .onChange(of: countryOfPublicInstances) { newCountry in
            InstancesManifest.shared.setPublicAccount(newCountry, asCurrent: AccountsModel.shared.current?.isPublic ?? true)
        }
        #if os(tvOS)
        .frame(maxWidth: 1000)
        #endif
        .navigationTitle("Advanced")
    }

    var logButton: some View {
        Button {
            #if os(macOS)
                NSWorkspace.shared.selectFile(MPVClient.logFile.path, inFileViewerRootedAtPath: YatteeApp.logsDirectory.path)
            #else
                presentingShareSheet = true
            #endif
        } label: {
            #if os(macOS)
                let labelText = "Open logs in Finder".localized()
            #else
                let labelText = "Share Logs...".localized()
            #endif
            Text(labelText)
        }
    }

    @ViewBuilder var advancedSettings: some View {
        Section(header: SettingsHeader(text: "MPV"), footer: mpvFooter) {
            showMPVPlaybackStatsToggle
            #if !os(tvOS)
                mpvEnableLoggingToggle
            #endif

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

            if mpvEnableLogging {
                logButton
            }
        }

        Section(header: SettingsHeader(text: "Cache")) {
            clearCacheButton
            cacheSize
        }
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

    var showMPVPlaybackStatsToggle: some View {
        Toggle("Show playback statistics", isOn: $showMPVPlaybackStats)
    }

    var mpvEnableLoggingToggle: some View {
        Toggle("Enable logging", isOn: $mpvEnableLogging)
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

    private var clearCacheButton: some View {
        Button {
            settings.presentAlert(
                Alert(
                    title: Text(
                        "Are you sure you want to clear cache?"
                    ),
                    primaryButton: .destructive(Text("Clear"), action: BaseCacheModel.shared.clear),
                    secondaryButton: .cancel()
                )
            )
        } label: {
            Text("Clear all")
                .foregroundColor(.red)
        }
    }

    var cacheSize: some View {
        Text(String(format: "Total size: %@", BaseCacheModel.shared.totalSizeFormatted))
            .foregroundColor(.secondary)
    }
}

struct AdvancedSettings_Previews: PreviewProvider {
    static var previews: some View {
        AdvancedSettings()
            .injectFixtureEnvironmentObjects()
    }
}
