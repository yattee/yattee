import AVFoundation
import Defaults
import Foundation
import MediaPlayer
import UIKit

final class AVPlayerBackend: PlayerBackend {
    static let assetKeysToLoad = ["tracks", "playable", "duration"]

    var model: PlayerModel!
    var controls: PlayerControlsModel!

    var stream: Stream?
    var video: Video?

    var currentTime: CMTime? {
        avPlayer.currentTime()
    }

    var loadedVideo: Bool {
        !avPlayer.currentItem.isNil
    }

    var isLoadingVideo: Bool {
        model.currentItem == nil || model.time == nil || !model.time!.isValid
    }

    var isPlaying: Bool {
        avPlayer.timeControlStatus == .playing
    }

    var playerItemDuration: CMTime? {
        avPlayer.currentItem?.asset.duration
    }

    private(set) var avPlayer = AVPlayer()
    var controller: AppleAVPlayerViewController?

    private var asset: AVURLAsset?
    private var composition = AVMutableComposition()
    private var loadedCompositionAssets = [AVMediaType]()

    private var frequentTimeObserver: Any?
    private var infrequentTimeObserver: Any?
    private var playerTimeControlStatusObserver: Any?

    private var statusObservation: NSKeyValueObservation?

    private var timeObserverThrottle = Throttle(interval: 2)

    init(model: PlayerModel, controls: PlayerControlsModel?) {
        self.model = model
        self.controls = controls

        addFrequentTimeObserver()
        addInfrequentTimeObserver()
        addPlayerTimeControlStatusObserver()
    }

    func bestPlayable(_ streams: [Stream]) -> Stream? {
        streams.first { $0.kind == .hls } ??
            streams.filter { $0.kind == .adaptive }.max { $0.resolution < $1.resolution } ??
            streams.first
    }

    func canPlay(_ stream: Stream) -> Bool {
        stream.kind == .hls || stream.kind == .stream || stream.videoFormat == "MPEG_4" ||
            (stream.videoFormat.starts(with: "video/mp4") && stream.encoding == "h264")
    }

    func playStream(
        _ stream: Stream,
        of video: Video,
        preservingTime: Bool,
        upgrading _: Bool
    ) {
        if let url = stream.singleAssetURL {
            model.logger.info("playing stream with one asset\(stream.kind == .hls ? " (HLS)" : ""): \(url)")
            loadSingleAsset(url, stream: stream, of: video, preservingTime: preservingTime)
        } else {
            model.logger.info("playing stream with many assets:")
            model.logger.info("composition audio asset: \(stream.audioAsset.url)")
            model.logger.info("composition video asset: \(stream.videoAsset.url)")

            loadComposition(stream, of: video, preservingTime: preservingTime)
        }
    }

    func play() {
        guard avPlayer.timeControlStatus != .playing else {
            return
        }

        avPlayer.play()
    }

    func pause() {
        guard avPlayer.timeControlStatus != .paused else {
            return
        }

        avPlayer.pause()
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func stop() {
        avPlayer.replaceCurrentItem(with: nil)
    }

    func seek(to time: CMTime, completionHandler: ((Bool) -> Void)?) {
        avPlayer.seek(
            to: time,
            toleranceBefore: .secondsInDefaultTimescale(1),
            toleranceAfter: .zero,
            completionHandler: completionHandler ?? { _ in }
        )
    }

    func seek(relative time: CMTime, completionHandler: ((Bool) -> Void)? = nil) {
        if let currentTime = currentTime {
            seek(to: currentTime + time, completionHandler: completionHandler)
        }
    }

    func setRate(_ rate: Float) {
        avPlayer.rate = rate
    }

    func closeItem() {
        avPlayer.replaceCurrentItem(with: nil)
    }

    func enterFullScreen() {
        controller?.playerView
            .perform(NSSelectorFromString("enterFullScreenAnimated:completionHandler:"), with: false, with: nil)
    }

    func exitFullScreen() {
        controller?.playerView
            .perform(NSSelectorFromString("exitFullScreenAnimated:completionHandler:"), with: false, with: nil)
    }

    #if os(tvOS)
        func closePiP(wasPlaying: Bool) {
            let item = avPlayer.currentItem
            let time = avPlayer.currentTime()

            avPlayer.replaceCurrentItem(with: nil)

            guard !item.isNil else {
                return
            }

            avPlayer.seek(to: time)
            avPlayer.replaceCurrentItem(with: item)

            guard wasPlaying else {
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.play()
            }
        }
    #else
        func closePiP(wasPlaying: Bool) {
            controller?.playerView.player = nil
            controller?.playerView.player = avPlayer

            guard wasPlaying else {
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.play()
            }
        }
    #endif

    func updateControls() {}
    func startControlsUpdates() {}
    func stopControlsUpdates() {}
    func setNeedsDrawing(_: Bool) {}

    private func loadSingleAsset(
        _ url: URL,
        stream: Stream,
        of video: Video,
        preservingTime: Bool = false
    ) {
        asset?.cancelLoading()
        asset = AVURLAsset(url: url)
        asset?.loadValuesAsynchronously(forKeys: Self.assetKeysToLoad) { [weak self] in
            var error: NSError?
            switch self?.asset?.statusOfValue(forKey: "duration", error: &error) {
            case .loaded:
                DispatchQueue.main.async { [weak self] in
                    self?.insertPlayerItem(stream, for: video, preservingTime: preservingTime)
                }
            case .failed:
                DispatchQueue.main.async { [weak self] in
                    self?.model.playerError = error
                }
            default:
                return
            }
        }
    }

    private func loadComposition(
        _ stream: Stream,
        of video: Video,
        preservingTime: Bool = false
    ) {
        loadedCompositionAssets = []
        loadCompositionAsset(stream.audioAsset, stream: stream, type: .audio, of: video, preservingTime: preservingTime, model: model)
        loadCompositionAsset(stream.videoAsset, stream: stream, type: .video, of: video, preservingTime: preservingTime, model: model)
    }

    private func loadCompositionAsset(
        _ asset: AVURLAsset,
        stream: Stream,
        type: AVMediaType,
        of video: Video,
        preservingTime: Bool = false,
        model: PlayerModel
    ) {
        asset.loadValuesAsynchronously(forKeys: Self.assetKeysToLoad) { [weak self] in
            guard let self = self else {
                return
            }
            model.logger.info("loading \(type.rawValue) track")

            let assetTracks = asset.tracks(withMediaType: type)

            guard let compositionTrack = self.composition.addMutableTrack(
                withMediaType: type,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                model.logger.critical("composition \(type.rawValue) addMutableTrack FAILED")
                return
            }

            guard let assetTrack = assetTracks.first else {
                model.logger.critical("asset \(type.rawValue) track FAILED")
                return
            }

            try! compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: CMTime.secondsInDefaultTimescale(video.length)),
                of: assetTrack,
                at: .zero
            )

            model.logger.critical("\(type.rawValue) LOADED")

            guard model.streamSelection == stream else {
                model.logger.critical("IGNORING LOADED")
                return
            }

            self.loadedCompositionAssets.append(type)

            if self.loadedCompositionAssets.count == 2 {
                self.insertPlayerItem(stream, for: video, preservingTime: preservingTime)
            }
        }
    }

    private func insertPlayerItem(
        _ stream: Stream,
        for video: Video,
        preservingTime: Bool = false
    ) {
        removeItemDidPlayToEndTimeObserver()

        model.playerItem = playerItem(stream)
        guard model.playerItem != nil else {
            return
        }

        addItemDidPlayToEndTimeObserver()
        attachMetadata(to: model.playerItem!, video: video, for: stream)

        DispatchQueue.main.async {
            self.stream = stream
            self.video = video
            self.model.stream = stream
            self.composition = AVMutableComposition()
            self.asset = nil
        }

        let startPlaying = {
            #if !os(macOS)
                try? AVAudioSession.sharedInstance().setActive(true)
            #endif

            if self.isAutoplaying(self.model.playerItem!) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self else {
                        return
                    }

                    if !preservingTime,
                       let segment = self.model.sponsorBlock.segments.first,
                       segment.start < 3,
                       self.model.lastSkipped.isNil
                    {
                        self.avPlayer.seek(
                            to: segment.endTime,
                            toleranceBefore: .secondsInDefaultTimescale(1),
                            toleranceAfter: .zero
                        ) { finished in
                            guard finished else {
                                return
                            }

                            self.model.lastSkipped = segment
                            self.model.play()
                        }
                    } else {
                        self.model.play()
                    }
                }
            }
        }

        let replaceItemAndSeek = {
            guard video == self.model.currentVideo else {
                return
            }
            self.avPlayer.replaceCurrentItem(with: self.model.playerItem)
            self.seekToPreservedTime { finished in
                guard finished else {
                    return
                }
                self.model.preservedTime = nil

                startPlaying()
            }
        }

        if preservingTime {
            if model.preservedTime.isNil {
                model.saveTime {
                    replaceItemAndSeek()
                    startPlaying()
                }
            } else {
                replaceItemAndSeek()
                startPlaying()
            }
        } else {
            avPlayer.replaceCurrentItem(with: model.playerItem)
            startPlaying()
        }
    }

    private func seekToPreservedTime(completionHandler: @escaping (Bool) -> Void = { _ in }) {
        guard let time = model.preservedTime else {
            return
        }

        avPlayer.seek(
            to: time,
            toleranceBefore: .secondsInDefaultTimescale(1),
            toleranceAfter: .zero,
            completionHandler: completionHandler
        )
    }

    private func playerItem(_: Stream) -> AVPlayerItem? {
        if let asset = asset {
            return AVPlayerItem(asset: asset)
        } else {
            return AVPlayerItem(asset: composition)
        }
    }

    private func attachMetadata(to item: AVPlayerItem, video: Video, for _: Stream? = nil) {
        #if !os(macOS)
            var externalMetadata = [
                makeMetadataItem(.commonIdentifierTitle, value: video.title),
                makeMetadataItem(.quickTimeMetadataGenre, value: video.genre ?? ""),
                makeMetadataItem(.commonIdentifierDescription, value: video.description ?? "")
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

        observePlayerItemStatus(item)
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

    func isAutoplaying(_ item: AVPlayerItem) -> Bool {
        avPlayer.currentItem == item
    }

    private func observePlayerItemStatus(_ item: AVPlayerItem) {
        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.old, .new]) { [weak self] playerItem, _ in
            guard let self = self else {
                return
            }

            switch playerItem.status {
            case .readyToPlay:
                if self.isAutoplaying(playerItem) {
                    self.model.play()
                }
            case .failed:
                self.model.playerError = item.error

            default:
                return
            }
        }
    }

    private func addItemDidPlayToEndTimeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidPlayToEndTime),
            name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
    }

    private func removeItemDidPlayToEndTimeObserver() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
    }

    @objc func itemDidPlayToEndTime() {
        model.prepareCurrentItemForHistory(finished: true)

        if model.queue.isEmpty {
            #if !os(macOS)
                try? AVAudioSession.sharedInstance().setActive(false)
            #endif
            model.resetQueue()
            #if os(tvOS)
                controller?.playerView.dismiss(animated: false) { [weak self] in
                    self?.controller?.dismiss(animated: true)
                }
            #else
                model.hide()
            #endif
        } else {
            model.advanceToNextItem()
        }
    }

    private func addFrequentTimeObserver() {
        let interval = CMTime.secondsInDefaultTimescale(0.5)

        frequentTimeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else {
                return
            }

            guard !self.model.currentItem.isNil else {
                return
            }

            self.controls.duration = self.playerItemDuration ?? .zero
            self.controls.currentTime = self.currentTime ?? .zero

            #if !os(tvOS)
                self.model.updateNowPlayingInfo()
            #endif

            if let currentTime = self.currentTime {
                self.model.handleSegments(at: currentTime)
            }
        }
    }

    private func addInfrequentTimeObserver() {
        let interval = CMTime.secondsInDefaultTimescale(5)

        infrequentTimeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else {
                return
            }

            guard !self.model.currentItem.isNil else {
                return
            }

            self.timeObserverThrottle.execute {
                self.model.updateWatch()
            }
        }
    }

    private func addPlayerTimeControlStatusObserver() {
        playerTimeControlStatusObserver = avPlayer.observe(\.timeControlStatus) { [weak self] player, _ in
            guard let self = self,
                  self.avPlayer == player
            else {
                return
            }

            DispatchQueue.main.async {
                self.controls.isPlaying = player.timeControlStatus == .playing
            }

            if player.timeControlStatus != .waitingToPlayAtSpecifiedRate {
                DispatchQueue.main.async { [weak self] in
                    self?.model.objectWillChange.send()
                }
            }

            if player.timeControlStatus == .playing, player.rate != self.model.currentRate {
                player.rate = self.model.currentRate
            }

            #if os(macOS)
                if player.timeControlStatus == .playing {
                    ScreenSaverManager.shared.disable(reason: "Yattee is playing video")
                } else {
                    ScreenSaverManager.shared.enable()
                }
            #endif

            self.timeObserverThrottle.execute {
                self.model.updateWatch()
            }
        }
    }
}
