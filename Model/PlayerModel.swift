import AVKit
import Defaults
import Foundation
import Logging
#if !os(macOS)
    import UIKit
#endif

final class PlayerModel: ObservableObject {
    let logger = Logger(label: "net.arekf.Pearvidious.ps")

    private(set) var player = AVPlayer()
    var controller: PlayerViewController?
    #if os(tvOS)
        var avPlayerViewController: AVPlayerViewController?
    #endif

    @Published var presentingPlayer = false

    @Published var stream: Stream?
    @Published var currentRate: Float?

    @Published var queue = [PlayerQueueItem]()
    @Published var currentItem: PlayerQueueItem!
    @Published var live = false
    @Published var time: CMTime?

    @Published var history = [PlayerQueueItem]()

    var api: InvidiousAPI
    var timeObserver: Any?

    private var statusObservation: NSKeyValueObservation?

    var isPlaying: Bool {
        stream != nil && currentRate != 0.0
    }

    init(api: InvidiousAPI? = nil) {
        self.api = api ?? InvidiousAPI()
        addItemDidPlayToEndTimeObserver()
    }

    func presentPlayer() {
        presentingPlayer = true
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard !isPlaying else {
            return
        }

        player.play()
    }

    func pause() {
        guard isPlaying else {
            return
        }

        player.pause()
    }

    func playVideo(_ video: Video) {
        if video.live {
            self.stream = nil

            playHlsUrl(video)
            return
        }

        guard let stream = video.streamWithResolution(Defaults[.quality].value) ?? video.defaultStream else {
            return
        }

        if stream.oneMeaningfullAsset {
            playStream(stream, for: video)
        } else {
            Task {
                await playComposition(video, for: stream)
            }
        }
    }

    private func playHlsUrl(_ video: Video) {
        player.replaceCurrentItem(with: playerItemWithMetadata(video))
        player.playImmediately(atRate: 1.0)
    }

    private func playStream(_ stream: Stream, for video: Video) {
        logger.warning("loading \(stream.description) to player")

        let playerItem: AVPlayerItem! = playerItemWithMetadata(video, for: stream)
        guard playerItem != nil else {
            return
        }

        if let index = queue.firstIndex(where: { $0.video.id == video.id }) {
            queue[index].playerItems.append(playerItem)
        }

        DispatchQueue.main.async {
            self.stream = stream
            self.player.replaceCurrentItem(with: playerItem)
        }

        if timeObserver.isNil {
            addTimeObserver()
        }
    }

    private func playComposition(_ video: Video, for stream: Stream) async {
        async let assetAudioTrack = stream.audioAsset.loadTracks(withMediaType: .audio)
        async let assetVideoTrack = stream.videoAsset.loadTracks(withMediaType: .video)

        logger.info("loading audio track")
        if let audioTrack = composition(video, for: stream)?.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
           let assetTrack = try? await assetAudioTrack.first
        {
            try! audioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: CMTime(seconds: video.length, preferredTimescale: 1000)),
                of: assetTrack,
                at: .zero
            )
            logger.critical("audio loaded")
        } else {
            logger.critical("NO audio track")
        }

        logger.info("loading video track")
        if let videoTrack = composition(video, for: stream)?.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
           let assetTrack = try? await assetVideoTrack.first
        {
            try! videoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: CMTime(seconds: video.length, preferredTimescale: 1000)),
                of: assetTrack,
                at: .zero
            )
            logger.critical("video loaded")
            playStream(stream, for: video)
        } else {
            logger.critical("NO video track")
        }
    }

    private func playerItem(_ video: Video, for stream: Stream? = nil) -> AVPlayerItem? {
        if stream != nil {
            if stream!.oneMeaningfullAsset {
                logger.info("stream has one meaningfull asset")
                return AVPlayerItem(asset: AVURLAsset(url: stream!.videoAsset.url))
            }
            if let composition = composition(video, for: stream!) {
                logger.info("stream has MANY assets, using composition")
                return AVPlayerItem(asset: composition)
            } else {
                return nil
            }
        }

        return AVPlayerItem(url: video.hlsUrl!)
    }

    private func playerItemWithMetadata(_ video: Video, for stream: Stream? = nil) -> AVPlayerItem? {
        logger.info("building player item metadata")
        let playerItemWithMetadata: AVPlayerItem! = playerItem(video, for: stream)
        guard playerItemWithMetadata != nil else {
            return nil
        }

        var externalMetadata = [
            makeMetadataItem(.commonIdentifierTitle, value: video.title),
            makeMetadataItem(.quickTimeMetadataGenre, value: video.genre),
            makeMetadataItem(.commonIdentifierDescription, value: video.description)
        ]

        #if !os(macOS)
            if let thumbnailData = try? Data(contentsOf: video.thumbnailURL(quality: .medium)!),
               let image = UIImage(data: thumbnailData),
               let pngData = image.pngData()
            {
                let artworkItem = makeMetadataItem(.commonIdentifierArtwork, value: pngData)
                externalMetadata.append(artworkItem)
            }

            playerItemWithMetadata.externalMetadata = externalMetadata
        #endif

        playerItemWithMetadata.preferredForwardBufferDuration = 15

        statusObservation?.invalidate()
        statusObservation = playerItemWithMetadata.observe(\.status, options: [.old, .new]) { playerItem, _ in
            switch playerItem.status {
            case .readyToPlay:
                if self.isAutoplaying(playerItem) {
                    self.player.play()
                }
            default:
                return
            }
        }

        logger.info("item metadata retrieved")
        return playerItemWithMetadata
    }

    func addItemDidPlayToEndTimeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidPlayToEndTime),
            name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    @objc func itemDidPlayToEndTime() {
        if queue.isEmpty {
            resetQueue()
            #if os(tvOS)
                avPlayerViewController!.dismiss(animated: true) {
                    self.controller!.dismiss(animated: true)
                }
            #endif
            presentingPlayer = false
        } else {
            advanceToNextItem()
        }
    }

    private func composition(_ video: Video, for stream: Stream) -> AVMutableComposition? {
        if let index = queue.firstIndex(where: { $0.video == video }) {
            if queue[index].compositions[stream].isNil {
                queue[index].compositions[stream] = AVMutableComposition()
            }
            return queue[index].compositions[stream]!
        }

        return nil
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 1000)

        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { _ in
            self.currentRate = self.player.rate
            self.live = self.currentVideo?.live ?? false
            self.time = self.player.currentTime()
        }
    }

    private func makeMetadataItem(_ identifier: AVMetadataIdentifier, value: Any) -> AVMetadataItem {
        let item = AVMutableMetadataItem()

        item.identifier = identifier
        item.value = value as? NSCopying & NSObjectProtocol
        item.extendedLanguageTag = "und"

        return item.copy() as! AVMetadataItem
    }
}
