import Defaults
import SwiftUI

struct ServicesSettings: View {
    @Default(.sponsorBlockInstance) private var sponsorBlock
    var body: some View {
        Section(header: Text("SponsorBlock API")) {
            TextField(
                "SponsorBlock API Instance",
                text: $sponsorBlock,
                prompt: Text("SponsorBlock API URL, leave blank to disable")
            )
            .labelsHidden()
            #if !os(macOS)
                .autocapitalization(.none)
                .keyboardType(.URL)
            #endif

            #if os(macOS)
                Spacer()
            #endif
        }
    }
}

struct ServicesSettings_Previews: PreviewProvider {
    static var previews: some View {
        ServicesSettings()
    }
}
