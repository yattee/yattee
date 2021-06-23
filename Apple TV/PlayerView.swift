import AVKit
import Foundation
import SwiftUI

struct PlayerView: View {
    @ObservedObject private var provider: VideoDetailsProvider

    init(id: String) {
        provider = VideoDetailsProvider(id)
    }

    var body: some View {
        VStack {
            pvc?
                .edgesIgnoringSafeArea(.all)
        }
        .task {
            Task.init {
                provider.load()
            }
        }
    }

    var pvc: PlayerViewController? {
        guard provider.video != nil else {
            return nil
        }

        return PlayerViewController(video: provider.video!)
    }
}
