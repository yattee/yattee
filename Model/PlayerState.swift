import AVFoundation
import Foundation
import Logging
#if !os(macOS)
    import UIKit
#endif

final class PlayerState: ObservableObject {
    let logger = Logger(label: "net.arekf.Pearvidious.ps")

    var video: Video!
    private(set) var composition = AVMutableComposition()
    private(set) var nextComposition = AVMutableComposition()

    private(set) var currentStream: Stream!

    private(set) var nextStream: Stream!
    private(set) var streamLoading = false

    private(set) var currentTime: CMTime?
    private(set) var savedTime: CMTime?

    var currentSegment: Segment?

    private(set) var profile = Profile()

    private(set) var currentRate: Float = 0.0
    static let availablePlaybackRates: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    var player: AVPlayer!

    var playerItem: AVPlayerItem {
        let playerItem = AVPlayerItem(asset: composition)

        var externalMetadata = [
            makeMetadataItem(.commonIdentifierTitle, value: video.title),
            makeMetadataItem(.quickTimeMetadataGenre, value: video.genre),
            makeMetadataItem(.commonIdentifierDescription, value: video.description)
        ]

        #if !os(macOS)
            if let thumbnailData = try? Data(contentsOf: video.thumbnailURL(quality: .high)!),
               let image = UIImage(data: thumbnailData),
               let pngData = image.pngData()
            {
                let artworkItem = makeMetadataItem(.commonIdentifierArtwork, value: pngData)
                externalMetadata.append(artworkItem)
            }

            playerItem.externalMetadata = externalMetadata
        #endif

        playerItem.preferredForwardBufferDuration = 10

        return playerItem
    }

    var segmentsProvider: SponsorBlockAPI?
    var timeObserver: Any?

    init(_ video: Video? = nil) {
        self.video = video

        if self.video != nil {
            segmentsProvider = SponsorBlockAPI(self.video.id)
            segmentsProvider!.load()
        }
    }

    deinit {
        destroyPlayer()
    }

    func loadVideo(_ video: Video?) {
        guard video != nil else {
            return
        }

        InvidiousAPI.shared.video(video!.id).load().onSuccess { response in
            if let video: Video = response.typedContent() {
                self.video = video
                Task {
                    let loadBest = self.profile.defaultStreamResolution == .hd720pFirstThenBest
                    await self.loadStream(video.defaultStreamForProfile(self.profile)!, loadBest: loadBest)
                }
            }
        }
    }

    func loadStream(_ stream: Stream, loadBest: Bool = false) async {
        nextStream?.cancelLoadingAssets()
//        removeTracksFromNextComposition()

        nextComposition = AVMutableComposition()

        DispatchQueue.main.async {
            self.streamLoading = true
            self.nextStream = stream
        }
        logger.info("replace streamToLoad: \(nextStream?.description ?? "nil"), streamLoading \(streamLoading)")

        await addTracksAndLoadAssets(stream, loadBest: loadBest)
    }

    fileprivate func addTracksAndLoadAssets(_ stream: Stream, loadBest: Bool = false) async {
        logger.info("adding tracks and loading assets for: \(stream.type), \(stream.description)")

        stream.assets.forEach { asset in
            Task.init {
                if try await asset.load(.isPlayable) {
                    handleAssetLoad(stream, asset: asset, type: asset == stream.videoAsset ? .video : .audio, loadBest: loadBest)

                    if stream.assetsLoaded {
                        logger.info("ALL assets loaded: \(stream.type), \(stream.description)")

                        playStream(stream)
                        
                        if loadBest {
                            await self.loadBestStream()
                        }
                    }
                }
            }
        }
    }

    fileprivate func handleAssetLoad(_ stream: Stream, asset: AVURLAsset, type: AVMediaType, loadBest _: Bool = false) {
        logger.info("handling asset load: \(stream.type), \(type) \(stream.description)")

        guard stream != currentStream else {
            logger.warning("IGNORING assets loaded: \(stream.type), \(stream.description)")
            return
        }

        addTrack(asset, stream: stream, type: type)
    }

    fileprivate func addTrack(_ asset: AVURLAsset, stream: Stream, type: AVMediaType? = nil) {
        let types: [AVMediaType] = stream.type == .adaptive ? [type!] : [.video, .audio]

        types.forEach { addTrackToNextComposition(asset, type: $0) }
    }

    fileprivate func loadBestStream() async {
        guard currentStream != video.bestStream else {
            return
        }

        if let bestStream = video.bestStream {
            await loadStream(bestStream)
        }
    }

    func streamDidLoad(_ stream: Stream?) {
        logger.info("didload stream: \(stream!.description)")

        currentStream?.cancelLoadingAssets()
        currentStream = stream
        streamLoading = nextStream != stream

        if nextStream == stream {
            nextStream = nil
        }

//        addTimeObserver()
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
//        guard player != nil else {
//            fatalError("player does not exists for playing")
//        }

        logger.warning("loading \(stream.description) to player")

        saveTime()
        replaceCompositionTracks()

        player!.replaceCurrentItem(with: playerItem)
        streamDidLoad(stream)

        DispatchQueue.main.async {
            self.player?.play()
            self.seekToSavedTime()
        }
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

        player?.currentItem?.tracks.forEach { $0.assetTrack?.asset?.cancelLoading() }

        currentStream?.cancelLoadingAssets()
        nextStream?.cancelLoadingAssets()

        player?.cancelPendingPrerolls()
        player?.replaceCurrentItem(with: nil)

        if timeObserver != nil {
            player?.removeTimeObserver(timeObserver!)
            timeObserver = nil
        }
        player = nil
        currentStream = nil
        nextStream = nil
    }

    func addTimeObserver() {
        let interval = CMTime(value: 1, timescale: 1)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard self.player != nil else {
                return
            }
            self.currentTime = time

            self.currentSegment = self.segmentsProvider?.segments.first { $0.timeInSegment(time) }

            if let segment = self.currentSegment {
                if self.profile.skippedSegmentsCategories.contains(segment.category) {
                    if segment.shouldSkip(self.currentTime!) {
                        self.player.seek(to: segment.skipTo)
                    }
                }
            }

            if self.player.rate != self.currentRate, self.player.rate != 0, self.currentRate != 0 {
                self.player.rate = self.currentRate
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

    func setPlayerRate(_ rate: Float) {
        currentRate = rate
        player.rate = rate
    }
}
