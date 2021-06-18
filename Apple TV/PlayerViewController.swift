import AVKit
import Foundation
import Logging
import SwiftUI

struct PlayerViewController: UIViewControllerRepresentable {
    let logger = Logger(label: "net.arekf.Pearvidious.pvc")

    @ObservedObject private var state: PlayerState

    var video: Video

    init(video: Video) {
        self.video = video
        state = PlayerState(video)

        loadStream(video.defaultStream, loadBest: true)
    }

    fileprivate func loadStream(_ stream: Stream?, loadBest: Bool = false) {
        if stream != state.nextStream {
            state.loadStream(stream)
            addTracksAndLoadAssets(stream!, loadBest: loadBest)
        }
    }

    fileprivate func addTracksAndLoadAssets(_ stream: Stream, loadBest: Bool = false) {
        logger.info("adding tracks and loading assets for: \(stream.type), \(stream.description)")

        stream.assets.forEach { asset in
            asset.loadValuesAsynchronously(forKeys: ["playable"]) {
                handleAssetLoad(stream, type: asset == stream.videoAsset ? .video : .audio, loadBest: loadBest)
            }
        }
    }

    fileprivate func handleAssetLoad(_ stream: Stream, type: AVMediaType, loadBest: Bool = false) {
        logger.info("handling asset load: \(stream.type), \(stream.description)")

        guard stream != state.currentStream else {
            logger.warning("IGNORING assets loaded: \(stream.type), \(stream.description)")
            return
        }

        stream.loadedAssets.forEach { asset in
            addTrack(asset, stream: stream, type: type)

            if stream.assetsLoaded {
                DispatchQueue.main.async {
                    logger.info("ALL assets loaded: \(stream.type), \(stream.description)")

                    state.playStream(stream)
                }

                if loadBest {
                    loadBestStream()
                }
            }
        }
    }

    fileprivate func addTrack(_ asset: AVURLAsset, stream: Stream, type: AVMediaType? = nil) {
        let types: [AVMediaType] = stream.type == .adaptive ? [type!] : [.video, .audio]

        types.forEach { state.addTrackToNextComposition(asset, type: $0) }
    }

    fileprivate func loadBestStream() {
        guard state.currentStream != video.bestStream else {
            return
        }

        loadStream(video.bestStream)
    }

    func makeUIViewController(context _: Context) -> StreamAVPlayerViewController {
        let controller = StreamAVPlayerViewController()
        controller.state = state

        #if os(tvOS)
            controller.transportBarCustomMenuItems = [streamingQualityMenu]
        #endif
        controller.modalPresentationStyle = .fullScreen
        controller.player = state.player

        return controller
    }

    func updateUIViewController(_ controller: StreamAVPlayerViewController, context _: Context) {
        var items: [UIMenuElement] = []

        if state.nextStream != nil {
            items.append(actionsMenu)
        }

        items.append(streamingQualityMenu)

        #if os(tvOS)
            controller.transportBarCustomMenuItems = items

            if let skip = skipSegmentAction {
                if controller.contextualActions.isEmpty {
                    controller.contextualActions = [skip]
                }
            } else {
                controller.contextualActions = []
            }
        #endif
    }

    fileprivate var streamingQualityMenu: UIMenu {
        UIMenu(title: "Streaming quality", image: UIImage(systemName: "waveform"), children: streamingQualityMenuActions)
    }

    fileprivate var streamingQualityMenuActions: [UIAction] {
        video.selectableStreams.map { stream in
            let image = self.state.currentStream == stream ? UIImage(systemName: "checkmark") : nil

            return UIAction(title: stream.description, image: image) { _ in
                guard state.currentStream != stream else {
                    return
                }

                loadStream(stream)
            }
        }
    }

    fileprivate var actionsMenu: UIMenu {
        UIMenu(title: "Actions", image: UIImage(systemName: "bolt.horizontal.fill"), children: [cancelLoadingAction])
    }

    fileprivate var cancelLoadingAction: UIAction {
        UIAction(title: "Cancel loading \(state.nextStream.description) stream") { _ in
            DispatchQueue.main.async {
                state.nextStream.cancelLoadingAssets()
                state.cancelLoadingStream(state.nextStream)
            }
        }
    }

    private var skipSegmentAction: UIAction? {
        if state.currentSegment == nil {
            return nil
        }

        return UIAction(title: "Skip \(state.currentSegment!.title())") { _ in
            DispatchQueue.main.async {
                state.player.seek(to: state.currentSegment!.skipTo)
            }
        }
    }
}
