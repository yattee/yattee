import Defaults
import SwiftUI

struct PlayerControlsSettings: View {
    @Default(.systemControlsCommands) private var systemControlsCommands
    @Default(.playerControlsLayout) private var playerControlsLayout
    @Default(.fullScreenPlayerControlsLayout) private var fullScreenPlayerControlsLayout
    @Default(.horizontalPlayerGestureEnabled) private var horizontalPlayerGestureEnabled
    @Default(.seekGestureSpeed) private var seekGestureSpeed
    @Default(.seekGestureSensitivity) private var seekGestureSensitivity
    @Default(.buttonBackwardSeekDuration) private var buttonBackwardSeekDuration
    @Default(.buttonForwardSeekDuration) private var buttonForwardSeekDuration
    @Default(.gestureBackwardSeekDuration) private var gestureBackwardSeekDuration
    @Default(.gestureForwardSeekDuration) private var gestureForwardSeekDuration
    @Default(.systemControlsSeekDuration) private var systemControlsSeekDuration
    @Default(.actionButtonShareEnabled) private var actionButtonShareEnabled
    @Default(.actionButtonSubscribeEnabled) private var actionButtonSubscribeEnabled
    @Default(.actionButtonNextEnabled) private var actionButtonNextEnabled
    @Default(.actionButtonCloseEnabled) private var actionButtonCloseEnabled
    @Default(.actionButtonAddToPlaylistEnabled) private var actionButtonAddToPlaylistEnabled
    @Default(.actionButtonSettingsEnabled) private var actionButtonSettingsEnabled
    @Default(.actionButtonHideEnabled) private var actionButtonHideEnabled
    @Default(.actionButtonNextQueueCountEnabled) private var actionButtonNextQueueCountEnabled

    #if os(iOS)
        @Default(.playerControlsLockOrientationEnabled) private var playerControlsLockOrientationEnabled
    #endif
    @Default(.playerControlsSettingsEnabled) private var playerControlsSettingsEnabled
    @Default(.playerControlsCloseEnabled) private var playerControlsCloseEnabled
    @Default(.playerControlsRestartEnabled) private var playerControlsRestartEnabled
    @Default(.playerControlsAdvanceToNextEnabled) private var playerControlsAdvanceToNextEnabled
    @Default(.playerControlsPlaybackModeEnabled) private var playerControlsPlaybackModeEnabled
    @Default(.playerControlsNextEnabled) private var playerControlsNextEnabled
    @Default(.playerControlsMusicModeEnabled) private var playerControlsMusicModeEnabled

    private var player = PlayerModel.shared

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
        .navigationTitle("Controls")
    }

    @ViewBuilder var sections: some View {
        #if !os(tvOS)
            Section(header: SettingsHeader(text: "Controls".localized()), footer: controlsLayoutFooter) {
                horizontalPlayerGestureEnabledToggle
                SettingsHeader(text: "Seek gesture sensitivity".localized(), secondary: true)
                seekGestureSensitivityPicker
                SettingsHeader(text: "Seek gesture speed".localized(), secondary: true)
                seekGestureSpeedPicker
                SettingsHeader(text: "Regular size".localized(), secondary: true)
                playerControlsLayoutPicker
                SettingsHeader(text: "Fullscreen size".localized(), secondary: true)
                fullScreenPlayerControlsLayoutPicker
            }
        #endif

        Section(header: SettingsHeader(text: "Seeking"), footer: seekingGestureSection) {
            systemControlsCommandsPicker

            seekingSection
        }

        #if os(macOS)
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    controlsButtonsSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading) {
                    actionsButtonsSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 10)
        #else

            controlsButtonsSection

            #if !os(tvOS)
                actionsButtonsSection
            #endif
        #endif
    }

    var controlsButtonsSection: some View {
        Section(header: SettingsHeader(text: "Controls Buttons")) {
            controlButtonToggles
        }
    }

    @ViewBuilder var actionsButtonsSection: some View {
        Section(header: SettingsHeader(text: "Actions Buttons")) {
            actionButtonToggles
        }

        actionButtonNextQueueCountEnabledToggle
    }

    private var systemControlsCommandsPicker: some View {
        func labelText(_ label: String) -> String {
            #if os(macOS)
                String(format: "System controls show buttons for %@".localized(), label)
            #else
                label
            #endif
        }

        return Picker("System controls buttons", selection: $systemControlsCommands) {
            Text(labelText("Seek".localized())).tag(SystemControlsCommands.seek)
            Text(labelText("Restart/Play next".localized())).tag(SystemControlsCommands.restartAndAdvanceToNext)
        }
        .onChange(of: systemControlsCommands) { _ in
            player.updateRemoteCommandCenter()
        }
        .modifier(SettingsPickerModifier())
    }

    @ViewBuilder private var controlsLayoutFooter: some View {
        #if os(iOS)
            Text("Large layout is not suitable for all devices and using it may cause controls not to fit on the screen.")
        #endif
    }

    private var horizontalPlayerGestureEnabledToggle: some View {
        Toggle("Seek with horizontal swipe on video", isOn: $horizontalPlayerGestureEnabled)
    }

    private var seekGestureSensitivityPicker: some View {
        Picker("Seek gesture sensitivity", selection: $seekGestureSensitivity) {
            Text("Highest").tag(1.0)
            Text("High").tag(10.0)
            Text("Normal").tag(30.0)
            Text("Low").tag(50.0)
            Text("Lowest").tag(100.0)
        }
        .disabled(!horizontalPlayerGestureEnabled)
        .modifier(SettingsPickerModifier())
    }

    private var seekGestureSpeedPicker: some View {
        Picker("Seek gesture speed", selection: $seekGestureSpeed) {
            ForEach([1, 0.75, 0.66, 0.5, 0.33, 0.25, 0.1], id: \.self) { value in
                Text(String(format: "%.0f%%", value * 100)).tag(value)
            }
        }
        .disabled(!horizontalPlayerGestureEnabled)
        .modifier(SettingsPickerModifier())
    }

    private var playerControlsLayoutPicker: some View {
        Picker("Regular Size", selection: $playerControlsLayout) {
            ForEach(PlayerControlsLayout.allCases.filter(\.available), id: \.self) { layout in
                Text(layout.description).tag(layout.rawValue)
            }
        }
        .modifier(SettingsPickerModifier())
    }

    private var fullScreenPlayerControlsLayoutPicker: some View {
        Picker("Fullscreen size", selection: $fullScreenPlayerControlsLayout) {
            ForEach(PlayerControlsLayout.allCases.filter(\.available), id: \.self) { layout in
                Text(layout.description).tag(layout.rawValue)
            }
        }
        .modifier(SettingsPickerModifier())
    }

    @ViewBuilder private var seekingSection: some View {
        seekingDurationSetting("System controls", $systemControlsSeekDuration)
            .foregroundColor(systemControlsCommands == .restartAndAdvanceToNext ? .secondary : .primary)
            .disabled(systemControlsCommands == .restartAndAdvanceToNext)
        seekingDurationSetting("Controls button: backwards", $buttonBackwardSeekDuration)
        seekingDurationSetting("Controls button: forwards", $buttonForwardSeekDuration)
        seekingDurationSetting("Gesture: backwards", $gestureBackwardSeekDuration)
        seekingDurationSetting("Gesture: fowards", $gestureForwardSeekDuration)
    }

    private var seekingGestureSection: some View {
        #if os(iOS)
            Text("Gesture settings control skipping interval for double tap gesture on left/right side of the player. Changing system controls settings requires restart.")
        #elseif os(macOS)
            Text("Gesture settings control skipping interval for double click on left/right side of the player. Changing system controls settings requires restart.")
                .foregroundColor(.secondary)
        #else
            Text("Gesture settings control skipping interval for remote arrow buttons (for 2nd generation Siri Remote or newer). Changing system controls settings requires restart.")
        #endif
    }

    private func seekingDurationSetting(_ name: String, _ value: Binding<String>) -> some View {
        HStack {
            Text(name)
                .frame(minWidth: 140, alignment: .leading)
            Spacer()

            HStack {
                #if !os(tvOS)
                    Label("Plus", systemImage: "plus")
                        .imageScale(.large)
                        .labelStyle(.iconOnly)
                        .padding(7)
                        .foregroundColor(.accentColor)
                    #if os(iOS)
                        .background(RoundedRectangle(cornerRadius: 4).strokeBorder(lineWidth: 1).foregroundColor(.accentColor))
                    #endif
                        .contentShape(Rectangle())
                        .onTapGesture {
                            var intValue = Int(value.wrappedValue) ?? 10
                            intValue += 5
                            if intValue <= 0 {
                                intValue = 5
                            }
                            value.wrappedValue = String(intValue)
                        }
                #endif

                #if os(tvOS)
                    let textFieldWidth = 100.00
                #else
                    let textFieldWidth = 30.00
                #endif

                TextField("Duration", text: value)
                    .frame(width: textFieldWidth, alignment: .trailing)
                    .multilineTextAlignment(.center)

                    .labelsHidden()
                #if !os(macOS)
                    .keyboardType(.numberPad)
                #endif

                #if !os(tvOS)
                    Label("Minus", systemImage: "minus")
                        .imageScale(.large)
                        .labelStyle(.iconOnly)
                        .padding(7)
                        .foregroundColor(.accentColor)
                    #if os(iOS)
                        .frame(minHeight: 35)
                        .background(RoundedRectangle(cornerRadius: 4).strokeBorder(lineWidth: 1).foregroundColor(.accentColor))
                    #endif
                        .contentShape(Rectangle())
                        .onTapGesture {
                            var intValue = Int(value.wrappedValue) ?? 10
                            intValue -= 5
                            if intValue <= 0 {
                                intValue = 5
                            }
                            value.wrappedValue = String(intValue)
                        }
                #endif
            }
        }
    }

    @ViewBuilder private var actionButtonToggles: some View {
        Toggle("Share", isOn: $actionButtonShareEnabled)
        Toggle("Add to Playlist", isOn: $actionButtonAddToPlaylistEnabled)
        Toggle("Subscribe/Unsubscribe", isOn: $actionButtonSubscribeEnabled)
        Toggle("Settings", isOn: $actionButtonSettingsEnabled)
        Toggle("Watch Next", isOn: $actionButtonNextEnabled)
        Toggle("Hide player", isOn: $actionButtonHideEnabled)
        Toggle("Close video", isOn: $actionButtonCloseEnabled)
    }

    @ViewBuilder private var controlButtonToggles: some View {
        #if os(iOS)
            Toggle("Lock orientation", isOn: $playerControlsLockOrientationEnabled)
        #endif
        Toggle("Settings", isOn: $playerControlsSettingsEnabled)
        #if !os(tvOS)
            Toggle("Close", isOn: $playerControlsCloseEnabled)
        #endif
        Toggle("Restart", isOn: $playerControlsRestartEnabled)
        Toggle("Play next item", isOn: $playerControlsAdvanceToNextEnabled)
        Toggle("Watch Next", isOn: $playerControlsNextEnabled)
        Toggle("Playback mode", isOn: $playerControlsPlaybackModeEnabled)
        #if !os(tvOS)
            Toggle("Music mode", isOn: $playerControlsMusicModeEnabled)
        #endif
    }

    var actionButtonNextQueueCountEnabledToggle: some View {
        Toggle("Count of items in queue in Watch Next button", isOn: $actionButtonNextQueueCountEnabled)
    }
}

struct PlayerControlsSettings_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading) {
            PlayerControlsSettings()
        }
        .frame(minHeight: 800)
    }
}
