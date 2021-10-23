import Defaults
import SwiftUI

struct PlaybackSettings: View {
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
            #elseif os(tvOS)
                .pickerStyle(.inline)
            #endif

            #if os(macOS)
                Spacer()
            #endif
        }
    }
}
