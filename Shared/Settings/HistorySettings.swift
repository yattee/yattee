import Defaults
import SwiftUI

struct HistorySettings: View {
    static let watchedThresholds = [50, 60, 70, 80, 90, 95, 100]

    @State private var presentingClearHistoryConfirmation = false

    @EnvironmentObject<PlayerModel> private var player

    @Default(.saveRecents) private var saveRecents
    @Default(.saveHistory) private var saveHistory
    @Default(.showWatchingProgress) private var showWatchingProgress
    @Default(.watchedThreshold) private var watchedThreshold
    @Default(.watchedVideoStyle) private var watchedVideoStyle
    @Default(.watchedVideoBadgeColor) private var watchedVideoBadgeColor
    @Default(.watchedVideoPlayNowBehavior) private var watchedVideoPlayNowBehavior
    @Default(.resetWatchedStatusOnPlaying) private var resetWatchedStatusOnPlaying

    var body: some View {
        Group {
            Section(header: SettingsHeader(text: "History")) {
                Toggle("Save recent queries and channels", isOn: $saveRecents)
                Toggle("Save history of played videos", isOn: $saveHistory)
                Toggle("Show progress of watching on thumbnails", isOn: $showWatchingProgress)
                    .disabled(!saveHistory)

                #if !os(tvOS)
                    watchedThresholdPicker
                    watchedVideoStylePicker
                    watchedVideoBadgeColorPicker
                    watchedVideoPlayNowBehaviorPicker
                    resetWatchedStatusOnPlayingToggle
                #endif
            }

            #if os(tvOS)
                watchedThresholdPicker
                watchedVideoStylePicker
                watchedVideoBadgeColorPicker
                watchedVideoPlayNowBehaviorPicker
                resetWatchedStatusOnPlayingToggle
            #endif

            #if os(macOS)
                Spacer()
            #endif

            clearHistoryButton
        }
    }

    private var watchedThresholdPicker: some View {
        Section(header: header("Mark video as watched after playing")) {
            Picker("Mark video as watched after playing", selection: $watchedThreshold) {
                ForEach(Self.watchedThresholds, id: \.self) { threshold in
                    Text("\(threshold)%").tag(threshold)
                }
            }
            .disabled(!saveHistory)
            .labelsHidden()

            #if os(iOS)
                .pickerStyle(.automatic)
            #elseif os(tvOS)
                .pickerStyle(.inline)
            #endif
        }
    }

    private var watchedVideoStylePicker: some View {
        Section(header: header("Mark watched videos with")) {
            Picker("Mark watched videos with", selection: $watchedVideoStyle) {
                Text("Nothing").tag(WatchedVideoStyle.nothing)
                Text("Badge").tag(WatchedVideoStyle.badge)
                Text("Decreased opacity").tag(WatchedVideoStyle.decreasedOpacity)
                Text("Badge & Decreased opacity").tag(WatchedVideoStyle.both)
            }
            .disabled(!saveHistory)
            .labelsHidden()

            #if os(iOS)
                .pickerStyle(.automatic)
            #elseif os(tvOS)
                .pickerStyle(.inline)
            #endif
        }
    }

    private var watchedVideoBadgeColorPicker: some View {
        Section(header: header("Badge color")) {
            Picker("Badge color", selection: $watchedVideoBadgeColor) {
                Text("Based on system color scheme").tag(WatchedVideoBadgeColor.colorSchemeBased)
                Text("Blue").tag(WatchedVideoBadgeColor.blue)
                Text("Red").tag(WatchedVideoBadgeColor.red)
            }
            .disabled(!saveHistory)
            .disabled(watchedVideoStyle == .decreasedOpacity)
            .labelsHidden()

            #if os(iOS)
                .pickerStyle(.automatic)
            #elseif os(tvOS)
                .pickerStyle(.inline)
            #endif
        }
    }

    private var watchedVideoPlayNowBehaviorPicker: some View {
        Section(header: header("When partially watched video is played")) {
            Picker("When partially watched video is played", selection: $watchedVideoPlayNowBehavior) {
                Text("Continue").tag(WatchedVideoPlayNowBehavior.continue)
                Text("Restart").tag(WatchedVideoPlayNowBehavior.restart)
            }
            .disabled(!saveHistory)
            .labelsHidden()

            #if os(iOS)
                .pickerStyle(.automatic)
            #elseif os(tvOS)
                .pickerStyle(.inline)
            #endif
        }
    }

    private var resetWatchedStatusOnPlayingToggle: some View {
        Toggle("Reset watched status when playing again", isOn: $resetWatchedStatusOnPlaying)
    }

    private var clearHistoryButton: some View {
        Button("Clear History") {
            presentingClearHistoryConfirmation = true
        }
        .alert(isPresented: $presentingClearHistoryConfirmation) {
            Alert(
                title: Text(
                    "Are you sure you want to clear history of watched videos?"
                ),
                message: Text(
                    "This cannot be undone. You might need to switch between views or restart the app to see changes."
                ),
                primaryButton: .destructive(Text("Clear All")) {
                    player.removeAllWatches()
                    presentingClearHistoryConfirmation = false
                },
                secondaryButton: .cancel()
            )
        }
        .foregroundColor(.red)
        .disabled(!saveHistory)
    }

    private func header(_ text: String) -> some View {
        #if os(iOS)
            return EmptyView()
        #elseif os(macOS)
            return Text(text)
                .opacity(saveHistory ? 1 : 0.3)
        #else
            return Text(text)
                .foregroundColor(.secondary)
                .opacity(saveHistory ? 1 : 0.2)
        #endif
    }
}

struct HistorySettings_Previews: PreviewProvider {
    static var previews: some View {
        HistorySettings()
            .injectFixtureEnvironmentObjects()
    }
}
