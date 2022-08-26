import Defaults
import SwiftUI

struct PlayerSettings: View {
    @Default(.instances) private var instances
    @Default(.playerInstanceID) private var playerInstanceID

    @Default(.playerSidebar) private var playerSidebar
    @Default(.showHistoryInPlayer) private var showHistory
    @Default(.showKeywords) private var showKeywords
    @Default(.pauseOnHidingPlayer) private var pauseOnHidingPlayer
    @Default(.closeLastItemOnPlaybackEnd) private var closeLastItemOnPlaybackEnd
    #if os(iOS)
        @Default(.honorSystemOrientationLock) private var honorSystemOrientationLock
        @Default(.enterFullscreenInLandscape) private var enterFullscreenInLandscape
        @Default(.rotateToPortraitOnExitFullScreen) private var rotateToPortraitOnExitFullScreen
    #endif
    @Default(.closePiPOnNavigation) private var closePiPOnNavigation
    @Default(.closePiPOnOpeningPlayer) private var closePiPOnOpeningPlayer
    @Default(.closePlayerOnOpeningPiP) private var closePlayerOnOpeningPiP
    #if !os(macOS)
        @Default(.closePlayerOnItemClose) private var closePlayerOnItemClose
        @Default(.pauseOnEnteringBackground) private var pauseOnEnteringBackground
        @Default(.closePiPAndOpenPlayerOnEnteringForeground) private var closePiPAndOpenPlayerOnEnteringForeground
    #endif

    @Default(.enableReturnYouTubeDislike) private var enableReturnYouTubeDislike
    @Default(.systemControlsCommands) private var systemControlsCommands

    @EnvironmentObject<PlayerModel> private var player

    #if os(iOS)
        private var idiom: UIUserInterfaceIdiom {
            UIDevice.current.userInterfaceIdiom
        }
    #endif

    var body: some View {
        Group {
            #if os(macOS)
                sections

                Spacer()
            #else
                List {
                    sections
                }
            #endif
        }
        #if os(tvOS)
        .frame(maxWidth: 1000)
        #elseif os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Player")
    }

    private var sections: some View {
        Group {
            Section(header: SettingsHeader(text: "Playback")) {
                sourcePicker
                pauseOnHidingPlayerToggle
                #if !os(macOS)
                    pauseOnEnteringBackgroundToogle
                    closePlayerOnItemCloseToggle
                #endif
                closeLastItemOnPlaybackEndToggle
                systemControlsCommandsPicker
            }

            Section(header: SettingsHeader(text: "Interface")) {
                #if os(iOS)
                    if idiom == .pad {
                        sidebarPicker
                    }
                #endif

                #if os(macOS)
                    sidebarPicker
                #endif

                keywordsToggle
                showHistoryToggle
                returnYouTubeDislikeToggle
            }

            #if os(iOS)
                Section(header: SettingsHeader(text: "Orientation")) {
                    if idiom == .pad {
                        enterFullscreenInLandscapeToggle
                    }
                    rotateToPortraitOnExitFullScreenToggle
                    honorSystemOrientationLockToggle
                }
            #endif

            Section(header: SettingsHeader(text: "Picture in Picture")) {
                closePiPOnNavigationToggle
                closePiPOnOpeningPlayerToggle
                closePlayerOnOpeningPiPToggle
                #if !os(macOS)
                    closePiPAndOpenPlayerOnEnteringForegroundToggle
                #endif
            }
        }
    }

    private var sourcePicker: some View {
        Picker("Source", selection: $playerInstanceID) {
            Text("Account Instance").tag(String?.none)

            ForEach(instances) { instance in
                Text(instance.description).tag(Optional(instance.id))
            }
        }
        .modifier(SettingsPickerModifier())
    }

    private var systemControlsCommandsPicker: some View {
        func labelText(_ label: String) -> String {
            #if os(macOS)
                "System controls show buttons for \(label)"
            #else
                label
            #endif
        }

        return Picker("System controls buttons", selection: $systemControlsCommands) {
            Text(labelText("10 seconds forwards/backwards")).tag(SystemControlsCommands.seek)
            Text(labelText("Restart/Play next")).tag(SystemControlsCommands.restartAndAdvanceToNext)
        }
        .onChange(of: systemControlsCommands) { _ in
            player.updateRemoteCommandCenter()
        }
        .modifier(SettingsPickerModifier())
    }

    private var sidebarPicker: some View {
        Picker("Sidebar", selection: $playerSidebar) {
            #if os(macOS)
                Text("Show sidebar").tag(PlayerSidebarSetting.always)
            #endif

            #if os(iOS)
                Text("Show sidebar when space permits").tag(PlayerSidebarSetting.whenFits)
            #endif

            Text("Hide sidebar").tag(PlayerSidebarSetting.never)
        }
        .modifier(SettingsPickerModifier())
    }

    private var keywordsToggle: some View {
        Toggle("Show keywords", isOn: $showKeywords)
    }

    private var showHistoryToggle: some View {
        Toggle("Show history", isOn: $showHistory)
    }

    private var returnYouTubeDislikeToggle: some View {
        Toggle("Enable Return YouTube Dislike", isOn: $enableReturnYouTubeDislike)
    }

    private var pauseOnHidingPlayerToggle: some View {
        Toggle("Pause when player is closed", isOn: $pauseOnHidingPlayer)
    }

    #if !os(macOS)
        private var pauseOnEnteringBackgroundToogle: some View {
            Toggle("Pause when entering background", isOn: $pauseOnEnteringBackground)
        }

        private var closePlayerOnItemCloseToggle: some View {
            Toggle("Close player when closing video", isOn: $closePlayerOnItemClose)
        }
    #endif

    private var closeLastItemOnPlaybackEndToggle: some View {
        Toggle("Close video after playing last in the queue", isOn: $closeLastItemOnPlaybackEnd)
    }

    #if os(iOS)
        private var honorSystemOrientationLockToggle: some View {
            Toggle("Honor orientation lock", isOn: $honorSystemOrientationLock)
                .disabled(!enterFullscreenInLandscape)
        }

        private var enterFullscreenInLandscapeToggle: some View {
            Toggle("Enter fullscreen in landscape", isOn: $enterFullscreenInLandscape)
        }

        private var rotateToPortraitOnExitFullScreenToggle: some View {
            Toggle("Rotate to portrait when exiting fullscreen", isOn: $rotateToPortraitOnExitFullScreen)
        }
    #endif

    private var closePiPOnNavigationToggle: some View {
        Toggle("Close PiP when starting playing other video", isOn: $closePiPOnNavigation)
    }

    private var closePiPOnOpeningPlayerToggle: some View {
        Toggle("Close PiP when player is opened", isOn: $closePiPOnOpeningPlayer)
    }

    private var closePlayerOnOpeningPiPToggle: some View {
        Toggle("Close player when starting PiP", isOn: $closePlayerOnOpeningPiP)
    }

    #if !os(macOS)
        private var closePiPAndOpenPlayerOnEnteringForegroundToggle: some View {
            Toggle("Close PiP and open player when application enters foreground", isOn: $closePiPAndOpenPlayerOnEnteringForeground)
        }
    #endif
}

struct PlayerSettings_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading) {
            PlayerSettings()
        }
        .injectFixtureEnvironmentObjects()
    }
}
