import AVKit
import Foundation
import SwiftUI

struct PlayerView: View {
    @ObservedObject private var provider: VideoDetailsProvider

    private var id: String

    init(id: String) {
        self.id = id
        provider = VideoDetailsProvider(id)
    }

    var body: some View {
        ZStack {
            if let video = provider.video {
                if video.url != nil {
                    PlayerViewController(video)
                        .edgesIgnoringSafeArea(.all)
                }

                if video.error {
                    Text("Video can not be loaded")
                }
            }
        }
        .task {
            async {
                provider.load()
            }
        }
    }
}

struct PlayerViewController: UIViewControllerRepresentable {
    var video: Video

    init(_ video: Video) {
        self.video = video
    }

    private var player: AVPlayer {
        let item = AVPlayerItem(url: video.url!)
        item.externalMetadata = [makeMetadataItem(.commonIdentifierTitle, value: video.title)]

        return AVPlayer(playerItem: item)
    }

    private func makeMetadataItem(_ identifier: AVMetadataIdentifier, value: Any) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as? NSCopying & NSObjectProtocol
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }

    func makeUIViewController(context _: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.modalPresentationStyle = .fullScreen
        controller.player = player
        controller.title = video.title
        controller.player?.play()
        return controller
    }

    func updateUIViewController(_: AVPlayerViewController, context _: Context) {}
}
