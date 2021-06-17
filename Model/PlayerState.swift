import AVFoundation
import Foundation
import Logging

final class PlayerState: ObservableObject {
    let logger = Logger(label: "net.arekf.Pearvidious.ps")

    var video: Video

    @Published private(set) var player: AVPlayer! = AVPlayer()
    private(set) var composition = AVMutableComposition()
    @Published private(set) var currentStream: Stream!

    @Published private(set) var streamToLoad: Stream!
    @Published private(set) var streamLoading = false

    @Published private(set) var currentTime: CMTime?
    @Published private(set) var savedTime: CMTime?
    @Published var currentSegment: Segment?

    var playerItem: AVPlayerItem {
        let playerItem = AVPlayerItem(asset: composition)

        playerItem.externalMetadata = [
            makeMetadataItem(.commonIdentifierTitle, value: video.title),
            makeMetadataItem(.quickTimeMetadataGenre, value: video.genre),
            makeMetadataItem(.commonIdentifierDescription, value: video.description)
        ]
        playerItem.preferredForwardBufferDuration = 10

        return playerItem
    }

    var segmentsProvider: SponsorBlockSegmentsProvider
    var timeObserver: Any?

    init(_ video: Video) {
        self.video = video
        segmentsProvider = SponsorBlockSegmentsProvider(video.id)

        segmentsProvider.load()
    }

    deinit {
        destroyPlayer()
    }

    func loadStream(_ stream: Stream?) {
        guard streamToLoad != stream else {
            return
        }

        streamToLoad?.cancelLoadingAssets()

        DispatchQueue.main.async {
            self.streamLoading = true
            self.streamToLoad = stream
        }
        logger.info("replace streamToLoad: \(streamToLoad?.description ?? "nil"), streamLoading \(streamLoading)")
    }

    func streamDidLoad(_ stream: Stream?) {
        logger.info("didload stream: \(stream!.description)")

        currentStream?.cancelLoadingAssets()
        currentStream = stream
        streamLoading = streamToLoad != stream

        if streamToLoad == stream {
            streamToLoad = nil
        }

        addTimeObserver()
    }

    func cancelLoadingStream(_ stream: Stream) {
        guard streamToLoad == stream else {
            return
        }

        streamToLoad = nil
        streamLoading = false

        logger.info("cancel streamToLoad: \(streamToLoad?.description ?? "nil"), streamLoading \(streamLoading)")
    }

    func playStream(_ stream: Stream) {
        guard player != nil else {
            return
        }

        logger.warning("loading \(stream.description) to player")

        saveTime()

        player.replaceCurrentItem(with: playerItem)
        streamDidLoad(stream)

        seekToSavedTime()
    }

    func saveTime() {
        guard player != nil else {
            return
        }

        let currentTime = player.currentTime()

        guard currentTime.seconds > 0 else {
            return
        }

        savedTime = currentTime
    }

    func seekToSavedTime() {
        guard player != nil else {
            return
        }

        if let time = savedTime {
            player.seek(to: time)
        }

        player.play()
    }

    func destroyPlayer() {
        logger.critical("destroying player")

        player.currentItem?.tracks.forEach { $0.assetTrack?.asset?.cancelLoading() }

        currentStream?.cancelLoadingAssets()
        streamToLoad?.cancelLoadingAssets()

        player.cancelPendingPrerolls()
        player.replaceCurrentItem(with: nil)

        if timeObserver != nil {
            player.removeTimeObserver(timeObserver!)
        }
    }

    func addTimeObserver() {
        let interval = CMTime(value: 1, timescale: 1)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            self.currentTime = time
            self.currentSegment = self.segmentsProvider.segments.first { $0.timeInSegment(time) }
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
