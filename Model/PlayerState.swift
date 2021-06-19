import AVFoundation
import Foundation
import Logging
import UIKit

final class PlayerState: ObservableObject {
    let logger = Logger(label: "net.arekf.Pearvidious.ps")

    var video: Video

    @Published private(set) var player: AVPlayer! = AVPlayer()
    @Published private(set) var composition = AVMutableComposition()
    @Published private(set) var nextComposition = AVMutableComposition()

    @Published private(set) var currentStream: Stream!

    @Published private(set) var nextStream: Stream!
    @Published private(set) var streamLoading = false

    @Published private(set) var currentTime: CMTime?
    @Published private(set) var savedTime: CMTime?

    @Published var currentSegment: Segment?

    private var profile = Profile()

    @Published private(set) var currentRate: Float = 0.0
    static let availablePlaybackRates: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    var playerItem: AVPlayerItem {
        let playerItem = AVPlayerItem(asset: composition)

        var externalMetadata = [
            makeMetadataItem(.commonIdentifierTitle, value: video.title),
            makeMetadataItem(.quickTimeMetadataGenre, value: video.genre),
            makeMetadataItem(.commonIdentifierDescription, value: video.description)
        ]

        if let thumbnailData = try? Data(contentsOf: video.thumbnailURL!),
           let image = UIImage(data: thumbnailData),
           let pngData = image.pngData()
        {
            let artworkItem = makeMetadataItem(.commonIdentifierArtwork, value: pngData)
            externalMetadata.append(artworkItem)
        }

        playerItem.externalMetadata = externalMetadata

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
        guard nextStream != stream else {
            return
        }

        nextStream?.cancelLoadingAssets()
        removeTracksFromNextComposition()

        DispatchQueue.main.async {
            self.streamLoading = true
            self.nextStream = stream
        }
        logger.info("replace streamToLoad: \(nextStream?.description ?? "nil"), streamLoading \(streamLoading)")
    }

    func streamDidLoad(_ stream: Stream?) {
        logger.info("didload stream: \(stream!.description)")

        currentStream?.cancelLoadingAssets()
        currentStream = stream
        streamLoading = nextStream != stream

        if nextStream == stream {
            nextStream = nil
        }

        addTimeObserver()
    }

    func cancelLoadingStream(_ stream: Stream) {
        guard nextStream == stream else {
            return
        }

        nextStream = nil
        streamLoading = false

        logger.info("cancel streamToLoad: \(nextStream?.description ?? "nil"), streamLoading \(streamLoading)")
    }

    func playStream(_ stream: Stream) {
        guard player != nil else {
            return
        }

        logger.warning("loading \(stream.description) to player")

        saveTime()
        replaceCompositionTracks()

        player.replaceCurrentItem(with: playerItem)
        streamDidLoad(stream)

        player.play()

        seekToSavedTime()
    }

    func addTrackToNextComposition(_ asset: AVURLAsset, type: AVMediaType) {
        guard let assetTrack = asset.tracks(withMediaType: type).first else {
            return
        }

        if let track = nextComposition.tracks(withMediaType: type).first {
            logger.info("removing \(type) track")
            nextComposition.removeTrack(track)
        }

        let track = nextComposition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid)!

        try! track.insertTimeRange(
            CMTimeRange(start: .zero, duration: CMTime(seconds: video.length, preferredTimescale: 1000)),
            of: assetTrack,
            at: .zero
        )

        logger.info("inserted \(type) track")
    }

    func replaceCompositionTracks() {
        logger.warning("replacing compositions")

        composition = AVMutableComposition()

        nextComposition.tracks.forEach { track in
            let newTrack = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid)!

            try? newTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: CMTime(seconds: video.length, preferredTimescale: 1000)),
                of: track,
                at: .zero
            )
        }
    }

    func removeTracksFromNextComposition() {
        nextComposition.tracks.forEach { nextComposition.removeTrack($0) }
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
            logger.info("seeking to \(time.seconds)")
            player.seek(to: time)
        }
    }

    func destroyPlayer() {
        logger.critical("destroying player")

        player.currentItem?.tracks.forEach { $0.assetTrack?.asset?.cancelLoading() }

        currentStream?.cancelLoadingAssets()
        nextStream?.cancelLoadingAssets()

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

            let currentSegment = self.segmentsProvider.segments.first { $0.timeInSegment(time) }

            if let segment = currentSegment {
                if self.profile.skippedSegmentsCategories.contains(segment.category) {
                    if segment.shouldSkip(self.currentTime!) {
                        self.player.seek(to: segment.skipTo)
                    }
                }
            }

            if self.player.rate != self.currentRate, self.player.rate != 0, self.currentRate != 0 {
                self.player.rate = self.currentRate
            }

            self.currentSegment = currentSegment
        }
    }

    private func makeMetadataItem(_ identifier: AVMetadataIdentifier, value: Any) -> AVMetadataItem {
        let item = AVMutableMetadataItem()

        item.identifier = identifier
        item.value = value as? NSCopying & NSObjectProtocol
        item.extendedLanguageTag = "und"

        return item.copy() as! AVMetadataItem
    }

    func setPlayerRate(_ rate: Float) {
        currentRate = rate
        player.rate = rate
    }
}
