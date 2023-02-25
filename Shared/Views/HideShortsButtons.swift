import SwiftUI

struct HideShortsButtons: View {
    @Binding var hide: Bool

    var body: some View {
        Button {
            hide.toggle()
        } label: {
            Group {
                if hide {
                    Label("Short videos: hidden", systemImage: "bolt.slash.fill")
                        .help("Short videos: hidden")
                } else {
                    Label("Short videos: visible", systemImage: "bolt.fill")
                        .help("Short videos: visible")
                }
            }
            #if os(tvOS)
            .font(.caption2)
            .imageScale(.small)
            #endif
        }
    }
}

struct HideShortsButtons_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            HideShortsButtons(hide: .constant(true))
        }
    }
}
