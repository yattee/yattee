import Defaults
import SwiftUI

struct PlaybackSettings: View {
    @Default(.instances) private var instances
    @Default(.playerInstanceID) private var playerInstanceID
    @Default(.quality) private var quality
    @Default(.playerSidebar) private var playerSidebar
    @Default(.showKeywords) private var showKeywords
    @Default(.saveHistory) private var saveHistory

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
                Text(instance.longDescription).tag(Optional(instance.id))
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
}

struct PlaybackSettings_Previews: PreviewProvider {
    static var previews: some View {
        PlaybackSettings()
            .injectFixtureEnvironmentObjects()
    }
}
