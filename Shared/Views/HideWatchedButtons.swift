import Defaults
import SwiftUI

struct HideWatchedButtons: View {
    @Default(.hideWatched) private var hideWatched

    var body: some View {
        Button {
            hideWatched.toggle()
        } label: {
            Group {
                if hideWatched {
                    Label("Watched: hidden", systemImage: "clock")
                        .help("Watched: hidden")
                } else {
                    Label("Watched: visible", systemImage: "clock.fill")
                        .help("Watched: visible")
                }
            }
            #if os(tvOS)
            .font(.caption)
            .imageScale(.small)
            #endif
        }
        .transaction { t in t.disablesAnimations = true }
    }
}

struct HideWatchedButtons_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            HideWatchedButtons()
        }
    }
}
