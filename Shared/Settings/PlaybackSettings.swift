import Defaults
import SwiftUI

struct PlaybackSettings: View {
    @Default(.quality) private var quality
    @Default(.playerSidebar) private var playerSidebar

    #if os(iOS)
        private var idiom: UIUserInterfaceIdiom {
            UIDevice.current.userInterfaceIdiom
        }
    #endif

    var body: some View {
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

        #if os(iOS)
            if idiom == .pad {
                playerSidebarSection
            }
        #elseif os(macOS)
            playerSidebarSection
        #endif

        #if os(macOS)
            Spacer()
        #endif
    }

    private var playerSidebarSection: some View {
        Section(header: Text("Player Sidebar")) {
            Picker("Player Sidebar", selection: $playerSidebar) {
                #if os(macOS)
                    Text("Show").tag(PlayerSidebarSetting.always)
                #endif

                #if os(iOS)
                    Text("Show when space permits").tag(PlayerSidebarSetting.whenFits)
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
    }
}
