import AVKit
import Defaults
import Foundation
import Logging
import MediaPlayer
#if !os(macOS)
    import UIKit
#endif
import Siesta
import SwiftUI
import SwiftyJSON

final class PlayerModel: ObservableObject {
    static let availableRates: [Float] = [0.5, 0.67, 0.8, 1, 1.25, 1.5, 2]
    let logger = Logger(label: "stream.yattee.app")

    private(set) var player = AVPlayer()
    private(set) var playerView = Player()
    var controller: PlayerViewController? { didSet { playerView.controller = controller } }
    #if os(tvOS)
        var avPlayerViewController: AVPlayerViewController?
    #endif

    @Published var presentingPlayer = false { didSet { pauseOnPlayerDismiss() } }

    @Published var stream: Stream?
    @Published var currentRate: Float = 1.0 { didSet { player.rate = currentRate } }

    @Published var availableStreams = [Stream]() { didSet { handleAvailableStreamsChange() }}
    @Published var streamSelection: Stream? { didSet { rebuildTVMenu() } }

    @Published var queue = [PlayerQueueItem]() { didSet { Defaults[.queue] = queue } }
    @Published var currentItem: PlayerQueueItem! { didSet { Defaults[.lastPlayed] = currentItem } }
    @Published var history = [PlayerQueueItem]() { didSet { Defaults[.history] = history } }

    @Published var preservedTime: CMTime?

    @Published var playerNavigationLinkActive = false { didSet { pauseOnChannelPlayerDismiss() } }

    @Published var sponsorBlock = SponsorBlockAPI()
    @Published var segmentRestorationTime: CMTime?
    @Published var lastSkipped: Segment? { didSet { rebuildTVMenu() } }
    @Published var restoredSegments = [Segment]()

    @Published var channelWithDetails: Channel?

    var accounts: AccountsModel
    var comments: CommentsModel

    var composition = AVMutableComposition()
    var loadedCompositionAssets = [AVMediaType]()

    private var currentArtwork: MPMediaItemArtwork?
    private var frequentTimeObserver: Any?
    private var infrequentTimeObserver: Any?
    private var playerTimeControlStatusObserver: Any?

    private var statusObservation: NSKeyValueObservation?

    private var timeObserverThrottle = Throttle(interval: 2)

    var playingInPictureInPicture = false

    @Published var presentingErrorDetails = false
    var playerError: Error? { didSet {
        #if !os(tvOS)
            if !playerError.isNil {
                presentingErrorDetails = true
            }
        #endif
    }}

    init(accounts: AccountsModel? = nil, comments: CommentsModel? = nil) {
        self.accounts = accounts ?? AccountsModel()
        self.comments = comments ?? CommentsModel()

        addItemDidPlayToEndTimeObserver()
        addFrequentTimeObserver()
        addInfrequentTimeObserver()
        addPlayerTimeControlStatusObserver()
    }

    func presentPlayer() {
        presentingPlayer = true
    }

    func togglePlayer() {
        presentingPlayer.toggle()
    }

    var isPlaying: Bool {
        player.timeControlStatus == .playing
    }

    var time: CMTime? {
        currentItem?.playbackTime
    }

    var live: Bool {
        currentItem?.video?.live ?? false
    }

    var playerItemDuration: CMTime? {
        player.currentItem?.asset.duration
    }

    var videoDuration: TimeInterval? {
        currentItem?.duration ?? currentVideo?.length
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard player.timeControlStatus != .playing else {
            return
        }

        player.play()
    }

    func pause() {
        guard player.timeControlStatus != .paused else {
            return
        }

        player.pause()
    }

    func upgradeToStream(_ stream: Stream) {
        if !self.stream.isNil, self.stream != stream {
            playStream(stream, of: currentVideo!, preservingTime: true, upgrading: true)
        }
    }

    func playStream(
        _ stream: Stream,
        of video: Video,
        preservingTime: Bool = false,
        upgrading: Bool = false
    ) {
        playerError = nil
        if !upgrading {
            resetSegments()

            sponsorBlock.loadSegments(
                videoID: video.videoID,
                categories: Defaults[.sponsorBlockCategories]
            ) { [weak self] in
                if Defaults[.showChannelSubscribers] {
                    self?.loadCurrentItemChannelDetails()
                }
            }
        }

        if let url = stream.singleAssetURL {
            logger.info("playing stream with one asset\(stream.kind == .hls ? " (HLS)" : ""): \(url)")

            insertPlayerItem(stream, for: video, preservingTime: preservingTime)
        } else {
            logger.info("playing stream with many assets:")
            logger.info("composition audio asset: \(stream.audioAsset.url)")
            logger.info("composition video asset: \(stream.videoAsset.url)")

            loadComposition(stream, of: video, preservingTime: preservingTime)
        }

        if !upgrading {
            updateCurrentArtwork()
        }
    }

    private func handleAvailableStreamsChange() {
        rebuildTVMenu()

        guard stream.isNil else {
            return
        }

        guard let stream = preferredStream(availableStreams) else {
            return
        }

        streamSelection = stream
        playStream(
            stream,
            of: currentVideo!,
            preservingTime: !currentItem.playbackTime.isNil
        )
    }
            }
        }
    }

    private func pauseOnChannelPlayerDismiss() {
        if !playingInPictureInPicture, !playerNavigationLinkActive {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.pause()
            }
        }
    }

    private func insertPlayerItem(
        _ stream: Stream,
        for video: Video,
        preservingTime: Bool = false
    ) {
        let playerItem = playerItem(stream)
        guard playerItem != nil else {
            return
        }

        attachMetadata(to: playerItem!, video: video, for: stream)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                return
            }

            self.stream = stream
            self.composition = AVMutableComposition()
        }

        let startPlaying = {
            #if !os(macOS)
                try? AVAudioSession.sharedInstance().setActive(true)
            #endif

            if self.isAutoplaying(playerItem!) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self else {
                        return
                    }

                    if let segment = self.sponsorBlock.segments.first,
                       segment.start < 3,
                       self.lastSkipped.isNil
                    {
                        self.player.seek(
                            to: segment.endTime,
                            toleranceBefore: .secondsInDefaultTimescale(1),
                            toleranceAfter: .zero
                        ) { finished in
                            guard finished else {
                                return
                            }

                            self.lastSkipped = segment
                            self.play()
                        }
                    } else {
                        self.play()
                    }
                }
            }
        }

        let replaceItemAndSeek = {
            self.player.replaceCurrentItem(with: playerItem)
            self.seekToPreservedTime { finished in
                guard finished else {
                    return
                }
                self.preservedTime = nil

                startPlaying()
            }
        }

        if preservingTime {
            if preservedTime.isNil {
                saveTime {
                    replaceItemAndSeek()
                    startPlaying()
                }
            } else {
                replaceItemAndSeek()
                startPlaying()
            }
        } else {
            player.replaceCurrentItem(with: playerItem)
            startPlaying()
        }
    }

    private func loadComposition(
        _ stream: Stream,
        of video: Video,
        preservingTime: Bool = false
    ) {
        loadedCompositionAssets = []
        loadCompositionAsset(stream.audioAsset, stream: stream, type: .audio, of: video, preservingTime: preservingTime)
        loadCompositionAsset(stream.videoAsset, stream: stream, type: .video, of: video, preservingTime: preservingTime)
    }

    private func loadCompositionAsset(
        _ asset: AVURLAsset,
        stream: Stream,
        type: AVMediaType,
        of video: Video,
        preservingTime: Bool = false
    ) {
        asset.loadValuesAsynchronously(forKeys: ["playable"]) { [weak self] in
            guard let self = self else {
                return
            }
            self.logger.info("loading \(type.rawValue) track")

            let assetTracks = asset.tracks(withMediaType: type)

            guard let compositionTrack = self.composition.addMutableTrack(
                withMediaType: type,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                self.logger.critical("composition \(type.rawValue) addMutableTrack FAILED")
                return
            }

            guard let assetTrack = assetTracks.first else {
                self.logger.critical("asset \(type.rawValue) track FAILED")
                return
            }

            try! compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: CMTime.secondsInDefaultTimescale(video.length)),
                of: assetTrack,
                at: .zero
            )

            self.logger.critical("\(type.rawValue) LOADED")

            guard self.streamSelection == stream else {
                self.logger.critical("IGNORING LOADED")
                return
            }

            self.loadedCompositionAssets.append(type)

            if self.loadedCompositionAssets.count == 2 {
                self.insertPlayerItem(stream, for: video, preservingTime: preservingTime)
            }
        }
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

        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.old, .new]) { [weak self] playerItem, _ in
            guard let self = self else {
                return
            }

            switch playerItem.status {
            case .readyToPlay:
                if self.isAutoplaying(playerItem) {
                    self.play()
                }
            case .failed:
                self.playerError = item.error

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
        currentItem.playbackTime = playerItemDuration

        if queue.isEmpty {
            #if !os(macOS)
                try? AVAudioSession.sharedInstance().setActive(false)
            #endif
            addCurrentItemToHistory()
            resetQueue()
            #if os(tvOS)
                avPlayerViewController!.dismiss(animated: true) { [weak self] in
                    self?.controller!.dismiss(animated: true)
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

        DispatchQueue.main.async { [weak self] in
            self?.preservedTime = currentTime
            completionHandler()
        }
    }

    private func seekToPreservedTime(completionHandler: @escaping (Bool) -> Void = { _ in }) {
        guard let time = preservedTime else {
            return
        }

        player.seek(
            to: time,
            toleranceBefore: .secondsInDefaultTimescale(1),
            toleranceAfter: .zero,
            completionHandler: completionHandler
        )
    }

    private func addFrequentTimeObserver() {
        let interval = CMTime.secondsInDefaultTimescale(0.5)

        frequentTimeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else {
                return
            }

            guard !self.currentItem.isNil else {
                return
            }

            #if !os(tvOS)
                self.updateNowPlayingInfo()
            #endif

            self.handleSegments(at: self.player.currentTime())
        }
    }

    private func addInfrequentTimeObserver() {
        let interval = CMTime.secondsInDefaultTimescale(5)

        infrequentTimeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else {
                return
            }

            guard !self.currentItem.isNil else {
                return
            }

            self.timeObserverThrottle.execute {
                self.updateCurrentItemIntervals()
            }
        }
    }

    private func addPlayerTimeControlStatusObserver() {
        playerTimeControlStatusObserver = player.observe(\.timeControlStatus) { [weak self] player, _ in
            guard let self = self,
                  self.player == player
            else {
                return
            }

            if player.timeControlStatus != .waitingToPlayAtSpecifiedRate {
                self.objectWillChange.send()
            }

            if player.timeControlStatus == .playing, player.rate != self.currentRate {
                player.rate = self.currentRate
            }

            #if os(macOS)
                if player.timeControlStatus == .playing {
                    ScreenSaverManager.shared.disable(reason: "Yattee is playing video")
                } else {
                    ScreenSaverManager.shared.enable()
                }
            #endif

            self.timeObserverThrottle.execute {
                self.updateCurrentItemIntervals()
            }
        }
    }

    private func updateCurrentItemIntervals() {
        currentItem?.playbackTime = player.currentTime()
        currentItem?.videoDuration = player.currentItem?.asset.duration.seconds
    }

    fileprivate func updateNowPlayingInfo() {
        var duration: Int?
        if !currentItem.video.live {
            let itemDuration = currentItem.videoDuration ?? 0
            duration = itemDuration.isFinite ? Int(itemDuration) : nil
        }
        var nowPlayingInfo: [String: AnyObject] = [
            MPMediaItemPropertyTitle: currentItem.video.title as AnyObject,
            MPMediaItemPropertyArtist: currentItem.video.author as AnyObject,
            MPMediaItemPropertyPlaybackDuration: duration as AnyObject,
            MPNowPlayingInfoPropertyIsLiveStream: currentItem.video.live as AnyObject,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime().seconds as AnyObject,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count as AnyObject,
            MPMediaItemPropertyMediaType: MPMediaType.anyVideo.rawValue as AnyObject
        ]

        if !currentArtwork.isNil {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = currentArtwork as AnyObject
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func updateCurrentArtwork() {
        guard let thumbnailData = try? Data(contentsOf: currentItem.video.thumbnailURL(quality: .medium)!) else {
            return
        }

        #if os(macOS)
            let image = NSImage(data: thumbnailData)
        #else
            let image = UIImage(data: thumbnailData)
        #endif

        if image.isNil {
            return
        }

        currentArtwork = MPMediaItemArtwork(boundsSize: image!.size) { _ in image! }
    }

    func loadCurrentItemChannelDetails() {
        guard let video = currentVideo,
              !video.channel.detailsLoaded
        else {
            return
        }

        if restoreLoadedChannel() {
            return
        }

        accounts.api.channel(video.channel.id).load().onSuccess { [weak self] response in
            if let channel: Channel = response.typedContent() {
                self?.channelWithDetails = channel
                withAnimation {
                    self?.currentItem.video.channel = channel
                }
            }
        }
    }

    @discardableResult func restoreLoadedChannel() -> Bool {
        if !currentVideo.isNil, channelWithDetails?.id == currentVideo!.channel.id {
            currentItem.video.channel = channelWithDetails!
            return true
        }

        return false
    }

    func rateLabel(_ rate: Float) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        return "\(formatter.string(from: NSNumber(value: rate))!)×"
    }

    func closeCurrentItem() {
        addCurrentItemToHistory()
        currentItem = nil
        player.replaceCurrentItem(with: nil)
    }
}
