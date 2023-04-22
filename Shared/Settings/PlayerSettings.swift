import Defaults
import SwiftUI

struct PlayerSettings: View {
    @Default(.instances) private var instances
    @Default(.playerInstanceID) private var playerInstanceID

    @Default(.playerSidebar) private var playerSidebar

    @Default(.showKeywords) private var showKeywords
    @Default(.pauseOnHidingPlayer) private var pauseOnHidingPlayer
    #if os(iOS)
        @Default(.honorSystemOrientationLock) private var honorSystemOrientationLock
        @Default(.enterFullscreenInLandscape) private var enterFullscreenInLandscape
        @Default(.rotateToPortraitOnExitFullScreen) private var rotateToPortraitOnExitFullScreen
    #endif
    @Default(.closePiPOnNavigation) private var closePiPOnNavigation
    @Default(.closePiPOnOpeningPlayer) private var closePiPOnOpeningPlayer
    @Default(.closePlayerOnOpeningPiP) private var closePlayerOnOpeningPiP
    #if !os(macOS)
        @Default(.pauseOnEnteringBackground) private var pauseOnEnteringBackground
        @Default(.closePiPAndOpenPlayerOnEnteringForeground) private var closePiPAndOpenPlayerOnEnteringForeground
    #endif

    @Default(.enableReturnYouTubeDislike) private var enableReturnYouTubeDislike

    @Default(.openWatchNextOnClose) private var openWatchNextOnClose
    @Default(.openWatchNextOnFinishedWatching) private var openWatchNextOnFinishedWatching
    @Default(.openWatchNextOnFinishedWatchingDelay) private var openWatchNextOnFinishedWatchingDelay
    @Default(.showInspector) private var showInspector

    @ObservedObject private var accounts = AccountsModel.shared

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
            Section(header: SettingsHeader(text: "Playback".localized())) {
                if !accounts.isEmpty {
                    sourcePicker
                }
                pauseOnHidingPlayerToggle
                #if !os(macOS)
                    pauseOnEnteringBackgroundToogle
                #endif
            }

            #if !os(tvOS)
                Section(header: SettingsHeader(text: "Inspector".localized())) {
                    inspectorVisibilityPicker
                }
            #endif

            Section(header: SettingsHeader(text: "Watch Next")) {
                openWatchNextOnFinishedWatchingToggle
                openWatchNextOnFinishedWatchingDelayTextField
                openWatchNextOnCloseToggle
            }

            let interface = Section(header: SettingsHeader(text: "Interface".localized())) {
                #if os(iOS)
                    if idiom == .pad {
                        sidebarPicker
                    }
                #endif

                #if os(macOS)
                    sidebarPicker
                #endif

                if !accounts.isEmpty {
                    keywordsToggle
                    returnYouTubeDislikeToggle
                }
            }

            #if os(tvOS)
                if !accounts.isEmpty {
                    interface
                }
            #elseif os(macOS)
                interface
            #elseif os(iOS)
                if idiom == .pad || !accounts.isEmpty {
                    interface
                }
            #endif

            #if os(iOS)
                Section(header: SettingsHeader(text: "Orientation".localized())) {
                    if idiom == .pad {
                        enterFullscreenInLandscapeToggle
                    }
                    rotateToPortraitOnExitFullScreenToggle
                    honorSystemOrientationLockToggle
                }
            #endif

            Section(header: SettingsHeader(text: "Picture in Picture".localized())) {
                closePiPOnNavigationToggle
                closePiPOnOpeningPlayerToggle
                closePlayerOnOpeningPiPToggle
                #if !os(macOS)
                    closePiPAndOpenPlayerOnEnteringForegroundToggle
                #endif
            }
        }
    }

    private var videoDetailsHeaderPadding: Double {
        #if os(macOS)
            5.0
        #else
            0.0
        #endif
    }

    private var sourcePicker: some View {
        Picker("Source", selection: $playerInstanceID) {
            Text("Instance of current account").tag(String?.none)

            ForEach(instances) { instance in
                Text(instance.description).tag(Optional(instance.id))
            }
        }
        .modifier(SettingsPickerModifier())
    }

    private var openWatchNextOnCloseToggle: some View {
        Toggle("Open after manual close of video", isOn: $openWatchNextOnClose)
    }

    private var openWatchNextOnFinishedWatchingToggle: some View {
        Toggle("Open after watching video", isOn: $openWatchNextOnFinishedWatching)
    }

    private var openWatchNextOnFinishedWatchingDelayTextField: some View {
        HStack {
            Text("Autoplay delay")
                .frame(minWidth: 140, alignment: .leading)
            #if !os(iOS)
                Spacer()
            #endif
            TextField("Delay", text: $openWatchNextOnFinishedWatchingDelay)
            #if !os(iOS)
                .frame(maxWidth: 100, alignment: .trailing)
            #endif
                .labelsHidden()
            #if !os(macOS)
                .keyboardType(.numberPad)
            #endif
        }
        .multilineTextAlignment(.trailing)
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
    #endif

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

    private var inspectorVisibilityPicker: some View {
        Picker("Visibility", selection: $showInspector) {
            Text("Always").tag(ShowInspectorSetting.always)
            Text("Only for local files and URLs").tag(ShowInspectorSetting.onlyLocal)
        }
        .labelsHidden()
    }
}

struct PlayerSettings_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading) {
            PlayerSettings()
        }
        .frame(minHeight: 800)
        .injectFixtureEnvironmentObjects()
    }
}
