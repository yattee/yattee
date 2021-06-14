import AVKit
import Foundation
import SwiftUI

struct PlayerViewController: UIViewControllerRepresentable {
    @ObservedObject private var state = PlayerState()
    @ObservedObject var video: Video

    var player = AVPlayer()
    var composition = AVMutableComposition()

    var audioTrack: AVMutableCompositionTrack {
        composition.tracks(withMediaType: .audio).first ?? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    }

    var videoTrack: AVMutableCompositionTrack {
        composition.tracks(withMediaType: .video).first ?? composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    }

    var playerItem: AVPlayerItem {
        let playerItem = AVPlayerItem(asset: composition)

        playerItem.externalMetadata = [makeMetadataItem(.commonIdentifierTitle, value: video.title)]

        return playerItem
    }

    init(video: Video) {
        self.video = video
        state.currentStream = video.defaultStream

        addTracksAndLoadAssets(state.currentStream!)
    }

    func addTracksAndLoadAssets(_ stream: Stream) {
        composition.removeTrack(audioTrack)
        composition.removeTrack(videoTrack)

        let keys = ["playable"]

        stream.audioAsset.loadValuesAsynchronously(forKeys: keys) {
            DispatchQueue.main.async {
                guard let track = stream.audioAsset.tracks(withMediaType: .audio).first else {
                    return
                }

                try? audioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: CMTime(seconds: video.length, preferredTimescale: 1)),
                    of: track,
                    at: .zero
                )

                handleAssetLoad(stream)
            }
        }

        stream.videoAsset.loadValuesAsynchronously(forKeys: keys) {
            DispatchQueue.main.async {
                guard let track = stream.videoAsset.tracks(withMediaType: .video).first else {
                    return
                }

                try? videoTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: CMTime(seconds: video.length, preferredTimescale: 1)),
                    of: track,
                    at: .zero
                )

                handleAssetLoad(stream)
            }
        }
    }

    func handleAssetLoad(_ stream: Stream) {
        var error: NSError?
        let status = stream.videoAsset.statusOfValue(forKey: "playable", error: &error)

        switch status {
        case .loaded:
            let resumeAt = player.currentTime()

            if resumeAt.seconds > 0 {
                state.seekTo = resumeAt
            }

            state.currentStream = stream

            player.replaceCurrentItem(with: playerItem)

            if let time = state.seekTo {
                player.seek(to: time)
            }

            player.play()

        default:
            if error != nil {
                print("loading error: \(error!)")
            }
        }
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

        controller.transportBarCustomMenuItems = [streamingQualityMenu]
        controller.modalPresentationStyle = .fullScreen
        controller.player = player

        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context _: Context) {
        controller.transportBarCustomMenuItems = [streamingQualityMenu]
    }

    var streamingQualityMenu: UIMenu {
        UIMenu(title: "Streaming quality", image: UIImage(systemName: "4k.tv"), children: streamingQualityMenuActions)
    }

    var streamingQualityMenuActions: [UIAction] {
        video.selectableStreams.map { stream in
            let image = self.state.currentStream == stream ? UIImage(systemName: "checkmark") : nil

            return UIAction(title: stream.description, image: image) { _ in
                DispatchQueue.main.async {
                    addTracksAndLoadAssets(stream)
                }
            }
        }
    }
}
