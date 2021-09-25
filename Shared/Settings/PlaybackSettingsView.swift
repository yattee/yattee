import Defaults
import SwiftUI

struct PlaybackSettingsView: View {
    @Default(.quality) private var quality

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
            #endif

            #if os(macOS)
                Spacer()
            #endif
        }
    }
}
