import AVKit
import Defaults
import Foundation
import Logging
#if !os(macOS)
    import UIKit
#endif
import Siesta
import SwiftyJSON

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

    @Published var availableStreams = [Stream]() { didSet { rebuildStreamsMenu() } }
    @Published var streamSelection: Stream? { didSet { rebuildStreamsMenu() } }

    @Published var queue = [PlayerQueueItem]()
    @Published var currentItem: PlayerQueueItem!
    @Published var live = false
    @Published var time: CMTime?

    @Published var history = [PlayerQueueItem]()

    @Published var savedTime: CMTime?

    @Published var composition = AVMutableComposition()

    var accounts: AccountsModel
    var instances: InstancesModel

    var timeObserver: Any?
    private var shouldResumePlaying = true
    private var statusObservation: NSKeyValueObservation?

    init(accounts: AccountsModel? = nil, instances: InstancesModel? = nil) {
        self.accounts = accounts ?? AccountsModel()
        self.instances = instances ?? InstancesModel()
        addItemDidPlayToEndTimeObserver()
        addTimeObserver()
    }

    func presentPlayer() {
        presentingPlayer = true
    }

    var isPlaying: Bool {
        player.timeControlStatus == .playing
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
        savedTime = nil
        shouldResumePlaying = true

        loadAvailableStreams(video) { streams in
            guard let stream = streams.first else {
                return
            }

            self.streamSelection = stream
            self.playStream(stream, of: video, forcePlay: true)
        }
    }

    func upgradeToStream(_ stream: Stream) {
        if !self.stream.isNil, self.stream != stream {
            playStream(stream, of: currentItem.video, preservingTime: true)
        }
    }

    func piped(_ instance: Instance) -> PipedAPI {
        PipedAPI(account: instance.anonymousAccount)
    }

    func invidious(_ instance: Instance) -> InvidiousAPI {
        InvidiousAPI(account: instance.anonymousAccount)
    }

    private func playStream(
        _ stream: Stream,
        of video: Video,
        forcePlay: Bool = false,
        preservingTime: Bool = false
    ) {
        if let url = stream.singleAssetURL {
            logger.info("playing stream with one asset\(stream.kind == .hls ? " (HLS)" : ""): \(url)")

            insertPlayerItem(stream, for: video, forcePlay: forcePlay, preservingTime: preservingTime)
        } else {
            logger.info("playing stream with many assets:")
            logger.info("composition audio asset: \(stream.audioAsset.url)")
            logger.info("composition video asset: \(stream.videoAsset.url)")

            Task {
                await self.loadComposition(stream, of: video, forcePlay: forcePlay, preservingTime: preservingTime)
            }
        }
    }

    private func insertPlayerItem(
        _ stream: Stream,
        for video: Video,
        forcePlay: Bool = false,
        preservingTime: Bool = false
    ) {
        let playerItem = playerItem(stream)

        guard playerItem != nil else {
            return
        }

        attachMetadata(to: playerItem!, video: video, for: stream)
        DispatchQueue.main.async {
            self.stream = stream
            self.composition = AVMutableComposition()
        }

        shouldResumePlaying = forcePlay || isPlaying

        if preservingTime {
            saveTime {
                self.player.replaceCurrentItem(with: playerItem)

                self.seekToSavedTime { finished in
                    guard finished else {
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        forcePlay || self.shouldResumePlaying ? self.play() : self.pause()
                        self.shouldResumePlaying = false
                    }
                }
            }
        } else {
            player.replaceCurrentItem(with: playerItem)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                forcePlay || self.shouldResumePlaying ? self.play() : self.pause()
                self.shouldResumePlaying = false
            }
        }
    }

    private func loadComposition(
        _ stream: Stream,
        of video: Video,
        forcePlay: Bool = false,
        preservingTime: Bool = false
    ) async {
        await loadCompositionAsset(stream.audioAsset, type: .audio, of: video)
        await loadCompositionAsset(stream.videoAsset, type: .video, of: video)

        guard streamSelection == stream else {
            logger.critical("IGNORING LOADED")
            return
        }

        insertPlayerItem(stream, for: video, forcePlay: forcePlay, preservingTime: preservingTime)
    }

    private func loadCompositionAsset(_ asset: AVURLAsset, type: AVMediaType, of video: Video) async {
        async let assetTracks = asset.loadTracks(withMediaType: type)

        logger.info("loading \(type.rawValue) track")
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: type,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            logger.critical("composition \(type.rawValue) addMutableTrack FAILED")
            return
        }

        guard let assetTrack = try? await assetTracks.first else {
            logger.critical("asset \(type.rawValue) track FAILED")
            return
        }

        try! compositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: CMTime(seconds: video.length, preferredTimescale: 1000)),
            of: assetTrack,
            at: .zero
        )

        logger.critical("\(type.rawValue) LOADED")
    }

    private func playerItem(_ stream: Stream) -> AVPlayerItem? {
        if let url = stream.singleAssetURL {
            return AVPlayerItem(asset: AVURLAsset(url: url))
        } else {
            return AVPlayerItem(asset: composition)
        }
    }

    private func attachMetadata(to item: AVPlayerItem, video: Video, for _: Stream? = nil) {
        #if !os(macOS)
            var externalMetadata = [
                makeMetadataItem(.commonIdentifierTitle, value: video.title),
                makeMetadataItem(.quickTimeMetadataGenre, value: video.genre),
                makeMetadataItem(.commonIdentifierDescription, value: video.description)
            ]
            if let thumbnailData = try? Data(contentsOf: video.thumbnailURL(quality: .medium)!),
               let image = UIImage(data: thumbnailData),
               let pngData = image.pngData()
            {
                let artworkItem = makeMetadataItem(.commonIdentifierArtwork, value: pngData)
                externalMetadata.append(artworkItem)
            }

            item.externalMetadata = externalMetadata
        #endif

        item.preferredForwardBufferDuration = 5

        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.old, .new]) { playerItem, _ in
            switch playerItem.status {
            case .readyToPlay:
                if self.isAutoplaying(playerItem), self.shouldResumePlaying {
                    self.play()
                }
            case .failed:
                print("item error: \(String(describing: item.error))")
                print((item.asset as! AVURLAsset).url)

            default:
                return
            }
        }
    }

    #if !os(macOS)
        private func makeMetadataItem(_ identifier: AVMetadataIdentifier, value: Any) -> AVMetadataItem {
            let item = AVMutableMetadataItem()

            item.identifier = identifier
            item.value = value as? NSCopying & NSObjectProtocol
            item.extendedLanguageTag = "und"

            return item.copy() as! AVMetadataItem
        }
    #endif

    private func addItemDidPlayToEndTimeObserver() {
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

    private func saveTime(completionHandler: @escaping () -> Void = {}) {
        let currentTime = player.currentTime()

        guard currentTime.seconds > 0 else {
            return
        }

        DispatchQueue.main.async {
            self.savedTime = currentTime
            completionHandler()
        }
    }

    private func seekToSavedTime(completionHandler: @escaping (Bool) -> Void = { _ in }) {
        guard let time = savedTime else {
            return
        }

        player.seek(
            to: time,
            toleranceBefore: .init(seconds: 1, preferredTimescale: 1000),
            toleranceAfter: .zero,
            completionHandler: completionHandler
        )
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 1000)

        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { _ in
            self.currentRate = self.player.rate
            self.live = self.currentVideo?.live ?? false
            self.time = self.player.currentTime()
        }
    }
}
