import AVKit
import Foundation
import SwiftUI

struct PlayerView: View {
    @ObservedObject private var provider: VideoDetailsProvider

    init(id: String) {
        provider = VideoDetailsProvider(id)
    }

    var body: some View {
        ZStack {
            if let video = provider.video {
                PlayerViewController(video: video)
                    .edgesIgnoringSafeArea(.all)
            }
        }
        .task {
            async {
                provider.load()
            }
        }
    }
}
