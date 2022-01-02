import Defaults
import SwiftUI

struct PlaybackSettings: View {
    @Default(.instances) private var instances
    @Default(.playerInstanceID) private var playerInstanceID
    @Default(.quality) private var quality
    @Default(.playerSidebar) private var playerSidebar
    @Default(.showHistoryInPlayer) private var showHistory
    @Default(.showKeywords) private var showKeywords
    @Default(.showChannelSubscribers) private var channelSubscribers
    @Default(.pauseOnHidingPlayer) private var pauseOnHidingPlayer
    @Default(.closePiPOnNavigation) private var closePiPOnNavigation
    @Default(.closePiPOnOpeningPlayer) private var closePiPOnOpeningPlayer
    #if !os(macOS)
        @Default(.closePiPAndOpenPlayerOnEnteringForeground) private var closePiPAndOpenPlayerOnEnteringForeground
    #endif

    #if os(iOS)
        private var idiom: UIUserInterfaceIdiom {
            UIDevice.current.userInterfaceIdiom
        }
    #endif

    var body: some View {
        Group {
            #if os(iOS)
                Section(header: SettingsHeader(text: "Player")) {
                    sourcePicker
                    qualityPicker

                    if idiom == .pad {
                        sidebarPicker
                    }

                    keywordsToggle
                    showHistoryToggle
                    channelSubscribersToggle
                    pauseOnHidingPlayerToggle
                }

                Section(header: SettingsHeader(text: "Picture in Picture")) {
                    closePiPOnNavigationToggle
                    closePiPOnOpeningPlayerToggle
                    closePiPAndOpenPlayerOnEnteringForegroundToggle
                }
            #else
                Section(header: SettingsHeader(text: "Source")) {
                    sourcePicker
                }

                Section(header: SettingsHeader(text: "Quality")) {
                    qualityPicker
                }

                #if os(macOS)
                    Section(header: SettingsHeader(text: "Sidebar")) {
                        sidebarPicker
                    }
                #endif

                keywordsToggle
                showHistoryToggle
                channelSubscribersToggle
                pauseOnHidingPlayerToggle

                Section(header: SettingsHeader(text: "Picture in Picture")) {
                    closePiPOnNavigationToggle
                    closePiPOnOpeningPlayerToggle
                    #if !os(macOS)
                        closePiPAndOpenPlayerOnEnteringForegroundToggle
                    #endif
                }
            #endif
        }

        #if os(macOS)
            Spacer()
        #endif
    }

    private var sourcePicker: some View {
        Picker("Source", selection: $playerInstanceID) {
            Text("Best available stream").tag(String?.none)

            ForEach(instances) { instance in
                Text(instance.description).tag(Optional(instance.id))
            }
        }
        .labelsHidden()
        #if os(iOS)
            .pickerStyle(.automatic)
        #elseif os(tvOS)
            .pickerStyle(.inline)
        #endif
    }

    private var qualityPicker: some View {
        Picker("Quality", selection: $quality) {
            ForEach(ResolutionSetting.allCases, id: \.self) { resolution in
                Text(resolution.description).tag(resolution)
            }
        }
        .labelsHidden()

        #if os(iOS)
            .pickerStyle(.automatic)
        #elseif os(tvOS)
            .pickerStyle(.inline)
        #endif
    }

    private var sidebarPicker: some View {
        Picker("Sidebar", selection: $playerSidebar) {
            #if os(macOS)
                Text("Show").tag(PlayerSidebarSetting.always)
            #endif

            #if os(iOS)
                Text("Show sidebar when space permits").tag(PlayerSidebarSetting.whenFits)
            #endif

            Text("Hide").tag(PlayerSidebarSetting.never)
        }
        .labelsHidden()

        #if os(iOS)
            .pickerStyle(.automatic)
        #elseif os(tvOS)
            .pickerStyle(.inline)
        #endif
    }

    private var keywordsToggle: some View {
        Toggle("Show video keywords", isOn: $showKeywords)
    }

    private var showHistoryToggle: some View {
        Toggle("Show history of videos", isOn: $showHistory)
    }

    private var channelSubscribersToggle: some View {
        Toggle("Show channel subscribers count", isOn: $channelSubscribers)
    }

    private var pauseOnHidingPlayerToggle: some View {
        Toggle("Pause when player is closed", isOn: $pauseOnHidingPlayer)
    }

    private var closePiPOnNavigationToggle: some View {
        Toggle("Close PiP when starting playing other video", isOn: $closePiPOnNavigation)
    }

    private var closePiPOnOpeningPlayerToggle: some View {
        Toggle("Close PiP when player is opened", isOn: $closePiPOnOpeningPlayer)
    }

    #if !os(macOS)
        private var closePiPAndOpenPlayerOnEnteringForegroundToggle: some View {
            Toggle("Close PiP and open player when application enters foreground", isOn: $closePiPAndOpenPlayerOnEnteringForeground)
        }
    #endif
}

struct PlaybackSettings_Previews: PreviewProvider {
    static var previews: some View {
        PlaybackSettings()
            .injectFixtureEnvironmentObjects()
    }
}
