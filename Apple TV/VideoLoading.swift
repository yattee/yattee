import SwiftUI

struct VideoLoading: View {
    var video: Video

    var body: some View {
        VStack {
            Spacer()

            VStack {
                Text(video.title)

                Text("Loading...")
            }

            Spacer()
        }
    }
}
