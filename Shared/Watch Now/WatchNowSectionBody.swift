import SwiftUI

struct WatchNowSectionBody: View {
    let label: String
    let videos: [Video]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.title3.bold())
                .foregroundColor(.secondary)
            #if os(tvOS)
                .padding(.leading, 40)
            #else
                .padding(.leading, 15)
            #endif

            VideosCellsHorizontal(videos: videos)
        }
    }
}
