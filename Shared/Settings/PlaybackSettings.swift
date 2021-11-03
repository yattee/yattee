import Defaults
import SwiftUI

struct PlaybackSettings: View {
    @Default(.quality) private var quality
    @Default(.playerSidebar) private var playerSidebar
    @Default(.showKeywords) private var showKeywords

    #if os(iOS)
        private var idiom: UIUserInterfaceIdiom {
            UIDevice.current.userInterfaceIdiom
        }
    #endif

    var body: some View {
        qualitySection

        #if !os(tvOS)
            playerSection
        #endif

        #if os(macOS)
            Spacer()
        #endif
    }

    private var qualitySection: some View {
        Section(header: Text("Quality")) {
            Picker("Quality", selection: $quality) {
                ForEach(Stream.ResolutionSetting.allCases, id: \.self) { resolution in
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
    }

    private var playerSection: some View {
        Section(header: Text("Player")) {
            #if os(iOS)
                if idiom == .pad {
                    sidebarPicker
                }
            #elseif os(macOS)
                sidebarPicker
            #endif

            Toggle("Show video keywords", isOn: $showKeywords)
        }
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
        .labelsHidden()

        #if os(iOS)
            .pickerStyle(.automatic)
        #elseif os(tvOS)
            .pickerStyle(.inline)
        #endif
    }
}
