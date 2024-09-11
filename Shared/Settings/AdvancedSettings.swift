import Defaults
import SwiftUI

struct AdvancedSettings: View {
    @Default(.showMPVPlaybackStats) private var showMPVPlaybackStats
    @Default(.mpvCacheSecs) private var mpvCacheSecs
    @Default(.mpvCachePauseWait) private var mpvCachePauseWait
    @Default(.mpvCachePauseInital) private var mpvCachePauseInital
    @Default(.mpvDeinterlace) private var mpvDeinterlace
    @Default(.mpvEnableLogging) private var mpvEnableLogging
    @Default(.mpvHWdec) private var mpvHWdec
    @Default(.mpvDemuxerLavfProbeInfo) private var mpvDemuxerLavfProbeInfo
    @Default(.mpvInitialAudioSync) private var mpvInitialAudioSync
    @Default(.mpvSetRefreshToContentFPS) private var mpvSetRefreshToContentFPS
    @Default(.showCacheStatus) private var showCacheStatus
    @Default(.feedCacheSize) private var feedCacheSize
    @Default(.showPlayNowInBackendContextMenu) private var showPlayNowInBackendContextMenu
    @Default(.videoLoadingRetryCount) private var videoLoadingRetryCount

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
        Section(header: SettingsHeader(text: "Advanced")) {
            showPlayNowInBackendButtonsToggle
            videoLoadingRetryCountField
        }

        Section(header: SettingsHeader(text: "MPV"), footer: mpvFooter) {
            showMPVPlaybackStatsToggle
            #if !os(tvOS)
                mpvEnableLoggingToggle
            #endif

            Toggle(isOn: $mpvCachePauseInital) {
                HStack {
                    Text("cache-pause-initial")
                    #if !os(tvOS)
                        Image(systemName: "link")
                            .accessibilityAddTraits([.isButton, .isLink])
                            .font(.footnote)
                        #if os(iOS)
                            .onTapGesture {
                                UIApplication.shared.open(URL(string: "https://mpv.io/manual/stable/#options-cache-pause-initial")!)
                            }
                        #elseif os(macOS)
                            .onTapGesture {
                                NSWorkspace.shared.open(URL(string: "https://mpv.io/manual/stable/#options-cache-pause-initial")!)
                            }
                            .onHover(perform: onHover(_:))
                        #endif
                    #endif
                }
            }

            HStack {
                Text("cache-secs")
                #if !os(tvOS)
                    Image(systemName: "link")
                        .accessibilityAddTraits([.isButton, .isLink])
                        .font(.footnote)
                    #if os(iOS)
                        .onTapGesture {
                            UIApplication.shared.open(URL(string: "https://mpv.io/manual/stable/#options-cache-secs")!)
                        }
                    #elseif os(macOS)
                        .onTapGesture {
                            NSWorkspace.shared.open(URL(string: "https://mpv.io/manual/stable/#options-cache-secs")!)
                        }
                        .onHover(perform: onHover(_:))
                    #endif

                #endif
                TextField("cache-secs", text: $mpvCacheSecs)
                #if !os(macOS)
                    .keyboardType(.numberPad)
                #endif
            }
            .multilineTextAlignment(.trailing)

            HStack {
                Group {
                    Text("cache-pause-wait")
                    #if !os(tvOS)
                        Image(systemName: "link")
                            .accessibilityAddTraits([.isButton, .isLink])
                            .font(.footnote)
                        #if os(iOS)
                            .onTapGesture {
                                UIApplication.shared.open(URL(string: "https://mpv.io/manual/stable/#options-cache-pause-wait")!)
                            }
                        #elseif os(macOS)
                            .onTapGesture {
                                NSWorkspace.shared.open(URL(string: "https://mpv.io/manual/stable/#options-cache-pause-wait")!)
                            }
                            .onHover(perform: onHover(_:))
                        #endif
                    #endif
                }.frame(minWidth: 140, alignment: .leading)

                TextField("cache-pause-wait", text: $mpvCachePauseWait)
                #if !os(macOS)
                    .keyboardType(.numberPad)
                #endif
            }
            .multilineTextAlignment(.trailing)

            Toggle(isOn: $mpvDeinterlace) {
                HStack {
                    Text("deinterlace")
                    #if !os(tvOS)
                        Image(systemName: "link")
                            .accessibilityAddTraits([.isButton, .isLink])
                            .font(.footnote)
                        #if os(iOS)
                            .onTapGesture {
                                UIApplication.shared.open(URL(string: "https://mpv.io/manual/stable/#options-deinterlace")!)
                            }
                        #elseif os(macOS)
                            .onTapGesture {
                                NSWorkspace.shared.open(URL(string: "https://mpv.io/manual/stable/#options-deinterlace")!)
                            }
                            .onHover(perform: onHover(_:))
                        #endif
                    #endif
                }
            }

            Toggle(isOn: $mpvInitialAudioSync) {
                HStack {
                    Text("initial-audio-sync")
                    #if !os(tvOS)
                        Image(systemName: "link")
                            .accessibilityAddTraits([.isButton, .isLink])
                            .font(.footnote)
                        #if os(iOS)
                            .onTapGesture {
                                UIApplication.shared.open(URL(string: "https://mpv.io/manual/stable/#options-initial-audio-sync")!)
                            }
                        #elseif os(macOS)
                            .onTapGesture {
                                NSWorkspace.shared.open(URL(string: "https://mpv.io/manual/stable/#options-initial-audio-sync")!)
                            }
                            .onHover(perform: onHover(_:))
                        #endif
                    #endif
                }
            }

            HStack {
                Text("hwdec")

                #if !os(tvOS)
                    Image(systemName: "link")
                        .accessibilityAddTraits([.isButton, .isLink])
                        .font(.footnote)
                    #if os(iOS)
                        .onTapGesture {
                            UIApplication.shared.open(URL(string: "https://mpv.io/manual/stable/#options-hwdec")!)
                        }
                    #elseif os(macOS)
                        .onTapGesture {
                            NSWorkspace.shared.open(URL(string: "https://mpv.io/manual/stable/#options-hwdec")!)
                        }
                        .onHover(perform: onHover(_:))
                    #endif
                #endif

                Picker("", selection: $mpvHWdec) {
                    ForEach(["auto", "auto-safe", "auto-copy"], id: \.self) {
                        Text($0)
                    }
                }
                #if !os(tvOS)
                .pickerStyle(MenuPickerStyle())
                #endif
            }

            HStack {
                Text("demuxer-lavf-probe-info")

                #if !os(tvOS)
                    Image(systemName: "link")
                        .accessibilityAddTraits([.isButton, .isLink])
                        .font(.footnote)
                    #if os(iOS)
                        .onTapGesture {
                            UIApplication.shared.open(URL(string: "https://mpv.io/manual/stable/#options-demuxer-lavf-probe-info")!)
                        }
                    #elseif os(macOS)
                        .onTapGesture {
                            NSWorkspace.shared.open(URL(string: "https://mpv.io/manual/stable/#options-demuxer-lavf-probe-info")!)
                        }
                        .onHover(perform: onHover(_:))
                    #endif
                #endif

                Picker("", selection: $mpvDemuxerLavfProbeInfo) {
                    ForEach(["yes", "no", "auto", "nostreams"], id: \.self) {
                        Text($0)
                    }
                }
                #if !os(tvOS)
                .pickerStyle(MenuPickerStyle())
                #endif
            }

            Toggle(isOn: $mpvSetRefreshToContentFPS) {
                HStack {
                    Text("Sync refresh rate with content FPS – EXPERIMENTAL")
                }
            }

            if mpvEnableLogging {
                logButton
            }
        }

        Section(header: SettingsHeader(text: "Cache"), footer: cacheSize) {
            showCacheStatusToggle
            feedCacheSizeTextField
            clearCacheButton
        }
    }

    @ViewBuilder var mpvFooter: some View {
        let url = "https://mpv.io/manual/stable/"

        VStack(alignment: .leading) {
            Text("Restart the app to apply the settings above.")
                .padding(.bottom, 1)
            VStack(alignment: .leading, spacing: 2) {
                #if os(tvOS)
                    Text("More info can be found in MPV reference manual:")
                    Text(url)
                #else
                    Text("Further information can be found in the ")
                        + Text("MPV reference manual").underline().bold()
                        + Text(" by clicking on the link icon next to the option.")
                #endif
            }
        }
        .foregroundColor(.secondary)
    }

    var showPlayNowInBackendButtonsToggle: some View {
        Toggle("Show video context menu options to force selected backend", isOn: $showPlayNowInBackendContextMenu)
    }

    private var videoLoadingRetryCountField: some View {
        HStack {
            Text("Maximum retries for video loading")
                .frame(minWidth: 200, alignment: .leading)
                .multilineTextAlignment(.leading)
            TextField("Limit", value: $videoLoadingRetryCount, formatter: NumberFormatter())
                .multilineTextAlignment(.trailing)
            #if !os(macOS)
                .keyboardType(.numberPad)
            #endif
        }
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

    private var feedCacheSizeTextField: some View {
        HStack {
            Text("Maximum feed items")
                .frame(minWidth: 200, alignment: .leading)
                .multilineTextAlignment(.leading)
            TextField("Limit", text: $feedCacheSize)
                .multilineTextAlignment(.trailing)
            #if !os(macOS)
                .keyboardType(.numberPad)
            #endif
        }
    }

    private var showCacheStatusToggle: some View {
        Toggle("Show cache status", isOn: $showCacheStatus)
    }

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
        Text(String(format: "Total size: %@".localized(), BaseCacheModel.shared.totalSizeFormatted))
            .foregroundColor(.secondary)
    }
}

struct AdvancedSettings_Previews: PreviewProvider {
    static var previews: some View {
        AdvancedSettings()
            .injectFixtureEnvironmentObjects()
    }
}
