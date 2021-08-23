import AVFoundation
import Foundation
import Logging
#if !os(macOS)
    import UIKit
#endif

final class PlayerState: ObservableObject {
    let logger = Logger(label: "net.arekf.Pearvidious.ps")

    var video: Video!

    var player: AVPlayer!

    private var compositions = [Stream: AVMutableComposition]()

    private(set) var savedTime: CMTime?

    private(set) var currentRate: Float = 0.0
    static let availableRates: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    var playbackState: PlaybackState
    var timeObserver: Any?

    let maxResolution: Stream.Resolution?

    var playingOutsideViewController = false

    init(_ video: Video? = nil, playbackState: PlaybackState, maxResolution: Stream.Resolution? = nil) {
        self.video = video
        self.playbackState = playbackState
        self.maxResolution = maxResolution
    }

    deinit {
        destroyPlayer()
    }

    func loadVideo(_ video: Video?) {
        guard video != nil else {
            return
        }

        playbackState.reset()

        loadExtendedVideoDetails(video) { video in
            self.video = video
            self.playVideo(video)
        }
    }

    func loadExtendedVideoDetails(_ video: Video?, onSuccess: @escaping (Video) -> Void) {
        guard video != nil else {
            return
        }

        InvidiousAPI.shared.video(video!.id).load().onSuccess { response in
            if let video: Video = response.typedContent() {
                onSuccess(video)
            }
        }
    }

    fileprivate func playVideo(_ video: Video) {
        if video.hlsUrl != nil {
            playHlsUrl()
            return
        }

        let stream = maxResolution != nil ? video.streamWithResolution(maxResolution!) : video.defaultStream

        guard stream != nil else {
            return
        }

        Task {
            await self.loadStream(stream!)

            if stream != video.bestStream {
                await self.loadBestStream()
            }
        }
    }

    fileprivate func playHlsUrl() {
        player.replaceCurrentItem(with: playerItemWithMetadata())
        player.playImmediately(atRate: 1.0)
    }

    fileprivate func loadStream(_ stream: Stream) async {
        if stream.oneMeaningfullAsset {
            DispatchQueue.main.async {
                self.playStream(stream)
            }

            return
        } else {
            await playComposition(for: stream)
        }
    }

    fileprivate func playStream(_ stream: Stream) {
        guard player != nil else {
            return
        }

        logger.warning("loading \(stream.description) to player")

        DispatchQueue.main.async {
            self.saveTime()
            self.player?.replaceCurrentItem(with: self.playerItemWithMetadata(for: stream))
            self.playbackState.stream = stream
            if self.timeObserver == nil {
                self.addTimeObserver()
            }
            self.player?.playImmediately(atRate: 1.0)
            self.seekToSavedTime()
        }
    }

    fileprivate func playComposition(for stream: Stream) async {
        async let assetAudioTrack = stream.audioAsset.loadTracks(withMediaType: .audio)
        async let assetVideoTrack = stream.videoAsset.loadTracks(withMediaType: .video)

        if let audioTrack = composition(for: stream).addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
           let assetTrack = try? await assetAudioTrack.first
        {
            try! audioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: CMTime(seconds: video.length, preferredTimescale: 1000)),
                of: assetTrack,
                at: .zero
            )
            logger.critical("audio loaded")
        } else {
            fatalError("no track")
        }

        if let videoTrack = composition(for: stream).addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
           let assetTrack = try? await assetVideoTrack.first
        {
            try! videoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: CMTime(seconds: video.length, preferredTimescale: 1000)),
                of: assetTrack,
                at: .zero
            )
            logger.critical("video loaded")

            playStream(stream)
        } else {
            fatalError("no track")
        }
    }

    fileprivate func playerItem(for stream: Stream? = nil) -> AVPlayerItem {
        if stream != nil {
            if stream!.oneMeaningfullAsset {
                return AVPlayerItem(asset: stream!.videoAsset, automaticallyLoadedAssetKeys: [.isPlayable])
            } else {
                return AVPlayerItem(asset: composition(for: stream!))
            }
        }

        return AVPlayerItem(url: video.hlsUrl!)
    }

    fileprivate func playerItemWithMetadata(for stream: Stream? = nil) -> AVPlayerItem {
        let playerItemWithMetadata = playerItem(for: stream)

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

            playerItemWithMetadata.externalMetadata = externalMetadata
        #endif

        playerItemWithMetadata.preferredForwardBufferDuration = 10

        return playerItemWithMetadata
    }

    func setPlayerRate(_ rate: Float) {
        currentRate = rate
        player.rate = rate
    }

    fileprivate func composition(for stream: Stream) -> AVMutableComposition {
        if compositions[stream] == nil {
            compositions[stream] = AVMutableComposition()
        }

        return compositions[stream]!
    }

    fileprivate func loadBestStream() async {
        if let bestStream = video.bestStream {
            await loadStream(bestStream)
        }
    }

    fileprivate func saveTime() {
        guard player != nil else {
            return
        }

        let currentTime = player.currentTime()

        guard currentTime.seconds > 0 else {
            return
        }

        savedTime = currentTime
    }

    fileprivate func seekToSavedTime() {
        guard player != nil else {
            return
        }

        if let time = savedTime {
            logger.info("seeking to \(time.seconds)")
            player.seek(to: time, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
        }
    }

    fileprivate func destroyPlayer() {
        logger.critical("destroying player")

        guard !playingOutsideViewController else {
            logger.critical("cannot destroy, playing outside view controller")
            return
        }

        player?.currentItem?.tracks.forEach { $0.assetTrack?.asset?.cancelLoading() }

        player?.replaceCurrentItem(with: nil)

        if timeObserver != nil {
            player?.removeTimeObserver(timeObserver!)
            timeObserver = nil
        }

        player = nil
    }

    fileprivate func addTimeObserver() {
        let interval = CMTime(value: 1, timescale: 1)

        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { _ in
            guard self.player != nil else {
                return
            }

            if self.player.rate != self.currentRate, self.player.rate != 0, self.currentRate != 0 {
                self.player.rate = self.currentRate
            }

            self.playbackState.time = self.player.currentTime()
        }
    }

    fileprivate func makeMetadataItem(_ identifier: AVMetadataIdentifier, value: Any) -> AVMetadataItem {
        let item = AVMutableMetadataItem()

        item.identifier = identifier
        item.value = value as? NSCopying & NSObjectProtocol
        item.extendedLanguageTag = "und"

        return item.copy() as! AVMetadataItem
    }
}
