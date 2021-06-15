import AVKit
import Foundation
import Logging
import SwiftUI

struct PlayerViewController: UIViewControllerRepresentable {
    @ObservedObject private var state = PlayerState()
    @ObservedObject var video: Video

    var player = AVPlayer()
    var composition = AVMutableComposition()

    let logger = Logger(label: "net.arekf.Pearvidious.pvc")

    var playerItem: AVPlayerItem {
        let playerItem = AVPlayerItem(asset: composition)

        playerItem.externalMetadata = [makeMetadataItem(.commonIdentifierTitle, value: video.title)]
        playerItem.preferredForwardBufferDuration = 10

        return playerItem
    }

    init(video: Video) {
        self.video = video

        loadStream(video.defaultStream)
    }

    func loadStream(_ stream: Stream?) {
        if stream != state.streamToLoad {
            state.loadStream(stream)
            addTracksAndLoadAssets(state.streamToLoad, loadBest: true)
        }
    }

    func loadBestStream() {
        guard state.currentStream != video.bestStream else {
            return
        }

        loadStream(video.bestStream)
    }

    func addTracksAndLoadAssets(_ stream: Stream, loadBest: Bool = false) {
        logger.info("adding tracks and loading assets for: \(stream.type), \(stream.description)")

        stream.assets.forEach { asset in
            asset.loadValuesAsynchronously(forKeys: ["playable"]) {
                handleAssetLoad(stream, type: asset == stream.videoAsset ? .video : .audio, loadBest: loadBest)
            }
        }
    }

    func addTrack(_ asset: AVURLAsset, type: AVMediaType) {
        guard let assetTrack = asset.tracks(withMediaType: type).first else {
            return
        }

        if let track = composition.tracks(withMediaType: type).first {
            logger.info("removing \(type) track")
            composition.removeTrack(track)
        }

        let track = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid)!

        try! track.insertTimeRange(
            CMTimeRange(start: .zero, duration: CMTime(seconds: video.length, preferredTimescale: 1)),
            of: assetTrack,
            at: .zero
        )

        logger.info("inserted \(type) track")
    }

    func handleAssetLoad(_ stream: Stream, type: AVMediaType, loadBest: Bool = false) {
        logger.info("handling asset load: \(stream.type), \(stream.description)")
        guard stream != state.currentStream else {
            logger.warning("IGNORING assets loaded: \(stream.type), \(stream.description)")
            return
        }

        let loadedAssets = stream.assets.filter { $0.statusOfValue(forKey: "playable", error: nil) == .loaded }

        loadedAssets.forEach { asset in
            logger.info("both assets loaded: \(stream.type), \(stream.description)")

            if stream.type == .stream {
                addTrack(asset, type: .video)
                addTrack(asset, type: .audio)
            } else {
                addTrack(asset, type: type)
            }

            if stream.assetsLoaded {
                let resumeAt = player.currentTime()
                if resumeAt.seconds > 0 {
                    state.seekTo = resumeAt
                }

                logger.warning("replacing player item")
                player.replaceCurrentItem(with: playerItem)
                state.streamDidLoad(stream)

                if let time = state.seekTo {
                    player.seek(to: time)
                }

                player.play()

                if loadBest {
                    loadBestStream()
                }
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
        controller.player?.automaticallyWaitsToMinimizeStalling = true

        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context _: Context) {
        var items: [UIMenuElement] = []

        if state.streamToLoad != nil {
            items.append(actionsMenu)
        }

        items.append(streamingQualityMenu)

        controller.transportBarCustomMenuItems = items
    }

    var streamingQualityMenu: UIMenu {
        UIMenu(title: "Streaming quality", image: UIImage(systemName: "waveform"), children: streamingQualityMenuActions)
    }

    var streamingQualityMenuActions: [UIAction] {
        video.selectableStreams.map { stream in
            let image = self.state.currentStream == stream ? UIImage(systemName: "checkmark") : nil

            return UIAction(title: stream.description, image: image) { _ in
                DispatchQueue.main.async {
                    guard state.currentStream != stream else {
                        return
                    }
                    state.streamToLoad = stream
                    addTracksAndLoadAssets(state.streamToLoad)
                }
            }
        }
    }

    var actionsMenu: UIMenu {
        UIMenu(title: "Actions", image: UIImage(systemName: "bolt.horizontal.fill"), children: [cancelLoadingAction])
    }

    var cancelLoadingAction: UIAction {
        UIAction(title: "Cancel loading \(state.streamToLoad.description) stream") { _ in
            DispatchQueue.main.async {
                state.streamToLoad.cancelLoadingAssets()
                state.cancelLoadingStream(state.streamToLoad)
            }
        }
    }
}
