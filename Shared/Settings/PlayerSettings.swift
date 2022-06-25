import Defaults
import SwiftUI

struct PlayerSettings: View {
    @Default(.instances) private var instances
    @Default(.playerInstanceID) private var playerInstanceID
    @Default(.quality) private var quality
    @Default(.commentsInstanceID) private var commentsInstanceID

    #if !os(tvOS)
        @Default(.commentsPlacement) private var commentsPlacement
    #endif

    @Default(.playerSidebar) private var playerSidebar
    @Default(.showHistoryInPlayer) private var showHistory
    @Default(.showKeywords) private var showKeywords
    @Default(.pauseOnHidingPlayer) private var pauseOnHidingPlayer
    @Default(.closeLastItemOnPlaybackEnd) private var closeLastItemOnPlaybackEnd
    #if os(iOS)
        @Default(.honorSystemOrientationLock) private var honorSystemOrientationLock
        @Default(.lockOrientationInFullScreen) private var lockOrientationInFullScreen
        @Default(.enterFullscreenInLandscape) private var enterFullscreenInLandscape
    #endif
    @Default(.closePiPOnNavigation) private var closePiPOnNavigation
    @Default(.closePiPOnOpeningPlayer) private var closePiPOnOpeningPlayer
    #if !os(macOS)
        @Default(.closePiPAndOpenPlayerOnEnteringForeground) private var closePiPAndOpenPlayerOnEnteringForeground
    #endif

    @Default(.enableReturnYouTubeDislike) private var enableReturnYouTubeDislike

    @Default(.showMPVPlaybackStats) private var showMPVPlaybackStats

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
                qualityPicker
                pauseOnHidingPlayerToggle
                closeLastItemOnPlaybackEndToggle
            }

            Section(header: SettingsHeader(text: "Comments")) {
                commentsInstancePicker
                #if !os(tvOS)
                    commentsPlacementPicker
                        .disabled(!CommentsModel.enabled)
                #endif
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

            Section(header: SettingsHeader(text: "Picture in Picture")) {
                closePiPOnNavigationToggle
                closePiPOnOpeningPlayerToggle
                #if !os(macOS)
                    closePiPAndOpenPlayerOnEnteringForegroundToggle
                #endif
            }

            #if os(iOS)
                Section(header: SettingsHeader(text: "Orientation")) {
                    if idiom == .pad {
                        enterFullscreenInLandscapeToggle
                    }
                    honorSystemOrientationLockToggle
                    lockOrientationInFullScreenToggle
                }
            #endif

            Section(header: SettingsHeader(text: "Debugging")) {
                showMPVPlaybackStatsToggle
            }
        }
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

    private var commentsInstancePicker: some View {
        Picker("Source", selection: $commentsInstanceID) {
            Text("Disabled").tag(Optional(""))

            ForEach(InstancesModel.all.filter { $0.app.supportsComments }) { instance in
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

    #if !os(tvOS)
        private var commentsPlacementPicker: some View {
            Picker("Placement", selection: $commentsPlacement) {
                Text("Below video description").tag(CommentsPlacement.info)
                Text("Separate tab").tag(CommentsPlacement.separate)
            }
            .labelsHidden()
            #if os(iOS)
                .pickerStyle(.automatic)
            #endif
        }
    #endif

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
        .labelsHidden()

        #if os(iOS)
            .pickerStyle(.automatic)
        #elseif os(tvOS)
            .pickerStyle(.inline)
        #endif
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

        private var lockOrientationInFullScreenToggle: some View {
            Toggle("Lock orientation in fullscreen", isOn: $lockOrientationInFullScreen)
                .disabled(!enterFullscreenInLandscape)
        }
    #endif

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

    private var showMPVPlaybackStatsToggle: some View {
        Toggle("Show MPV playback statistics", isOn: $showMPVPlaybackStats)
    }
}

struct PlaybackSettings_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading) {
            PlayerSettings()
        }
        .injectFixtureEnvironmentObjects()
    }
}
