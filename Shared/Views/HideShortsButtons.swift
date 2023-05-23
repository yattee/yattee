import Defaults
import SwiftUI

struct HideShortsButtons: View {
    @Default(.hideShorts) private var hideShorts

    var body: some View {
        Button {
            hideShorts.toggle()
        } label: {
            Group {
                if hideShorts {
                    Label("Short videos: hidden", systemImage: "bolt.slash.fill")
                        .help("Short videos: hidden")
                } else {
                    Label("Short videos: visible", systemImage: "bolt.fill")
                        .help("Short videos: visible")
                }
            }
            #if os(tvOS)
            .font(.caption)
            .imageScale(.small)
            #endif
        }
    }
}

struct HideShortsButtons_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            HideShortsButtons()
        }
    }
}
