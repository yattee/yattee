import AVKit
import CoreData
#if os(iOS)
    import CoreMotion
#endif
import Defaults
import Foundation
import Logging
import MediaPlayer
import Siesta
import SwiftUI
import SwiftyJSON
#if !os(macOS)
    import UIKit
#endif

final class PlayerModel: ObservableObject {
    static let availableRates: [Float] = [0.5, 0.67, 0.8, 1, 1.25, 1.5, 2]
    let logger = Logger(label: "stream.yattee.app")

    var avPlayerView = AppleAVPlayerView()
    var playerItem: AVPlayerItem?

    var mpvPlayerView = MPVPlayerView()

    @Published var presentingPlayer = false { didSet { handlePresentationChange() } }
    @Published var activeBackend = PlayerBackendType.mpv

    var avPlayerBackend: AVPlayerBackend!
    var mpvBackend: MPVBackend!

    var backends: [PlayerBackend] {
        [avPlayerBackend, mpvBackend]
    }

    var backend: PlayerBackend! {
        switch activeBackend {
        case .mpv:
            return mpvBackend
        case .appleAVPlayer:
            return avPlayerBackend
        }
    }

    @Published var playerSize: CGSize = .zero { didSet {
        backend.setSize(playerSize.width, playerSize.height)
    }}
    @Published var stream: Stream?
    @Published var currentRate: Float = 1.0 { didSet { backend.setRate(currentRate) } }

    @Published var availableStreams = [Stream]() { didSet { handleAvailableStreamsChange() } }
    @Published var streamSelection: Stream? { didSet { rebuildTVMenu() } }

    @Published var queue = [PlayerQueueItem]() { didSet { Defaults[.queue] = queue } }
    @Published var currentItem: PlayerQueueItem! { didSet { handleCurrentItemChange() } }
    @Published var historyVideos = [Video]()

    @Published var preservedTime: CMTime?

    @Published var playerNavigationLinkActive = false { didSet { handleNavigationViewPlayerPresentationChange() } }

    @Published var sponsorBlock = SponsorBlockAPI()
    @Published var segmentRestorationTime: CMTime?
    @Published var lastSkipped: Segment? { didSet { rebuildTVMenu() } }
    @Published var restoredSegments = [Segment]()

    @Published var returnYouTubeDislike = ReturnYouTubeDislikeAPI()

    #if os(iOS)
        @Published var motionManager: CMMotionManager!
        @Published var lockedOrientation: UIInterfaceOrientation?
        @Published var lastOrientation: UIInterfaceOrientation?
    #endif

    var accounts: AccountsModel
    var comments: CommentsModel
    var controls: PlayerControlsModel { didSet {
        backends.forEach { backend in
            var backend = backend
            backend.controls = controls
        }
    }}
    var context: NSManagedObjectContext = PersistenceController.shared.container.viewContext

    @Published var playingInPictureInPicture = false

    @Published var presentingErrorDetails = false
    var playerError: Error? { didSet {
        #if !os(tvOS)
            if !playerError.isNil {
                presentingErrorDetails = true
            }
        #endif
    }}

    @Default(.pauseOnHidingPlayer) private var pauseOnHidingPlayer
    @Default(.closePiPOnNavigation) var closePiPOnNavigation
    @Default(.closePiPOnOpeningPlayer) var closePiPOnOpeningPlayer

    #if !os(macOS)
        @Default(.closePiPAndOpenPlayerOnEnteringForeground) var closePiPAndOpenPlayerOnEnteringForeground
    #endif

    private var currentArtwork: MPMediaItemArtwork?

    init(accounts: AccountsModel? = nil, comments: CommentsModel? = nil, controls: PlayerControlsModel? = nil) {
        self.accounts = accounts ?? AccountsModel()
        self.comments = comments ?? CommentsModel()
        self.controls = controls ?? PlayerControlsModel()

        self.avPlayerBackend = AVPlayerBackend(model: self, controls: controls)
        self.mpvBackend = MPVBackend(model: self)

        self.activeBackend = Defaults[.activeBackend]
    }

    func show() {
        guard !presentingPlayer else {
            #if os(macOS)
                Windows.player.focus()
            #endif
            return
        }
        #if os(macOS)
            Windows.player.open()
            Windows.player.focus()
        #endif
        presentingPlayer = true
    }

    func hide() {
        controls.playingFullscreen = false
        presentingPlayer = false
        playerNavigationLinkActive = false

        #if os(iOS)
            if Defaults[.lockPortraitWhenBrowsing] {
                Orientation.lockOrientation(.portrait, andRotateTo: .portrait)
            }
        #endif
    }

    func togglePlayer() {
        #if os(macOS)
            if !presentingPlayer {
                Windows.player.open()
            }
            Windows.player.focus()
        #else
            if presentingPlayer {
                hide()
            } else {
                show()
            }
        #endif
    }

    var isLoadingVideo: Bool {
        guard !currentVideo.isNil else {
            return false
        }

        return backend.isLoadingVideo
    }

    var isPlaying: Bool {
        backend.isPlaying
    }

    var playerItemDuration: CMTime? {
        backend.playerItemDuration
    }

    var playerItemDurationWithoutSponsorSegments: CMTime? {
        (backend.playerItemDuration ?? .zero) - .secondsInDefaultTimescale(
            sponsorBlock.segments.reduce(0) { $0 + $1.duration }
        )
    }

    var videoDuration: TimeInterval? {
        currentItem?.duration ?? currentVideo?.length ?? playerItemDuration?.seconds
    }

    var time: CMTime? {
        currentItem?.playbackTime
    }

    var live: Bool {
        currentVideo?.live ?? false
    }

    func togglePlay() {
        backend.togglePlay()
    }

    func play() {
        backend.play()
    }

    func pause() {
        backend.pause()
    }

    func play(_ video: Video, at time: TimeInterval? = nil, inNavigationView: Bool = false) {
        playNow(video, at: time)

        guard !playingInPictureInPicture else {
            return
        }

        if inNavigationView {
            playerNavigationLinkActive = true
        } else {
            show()
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

            DispatchQueue.main.async { [weak self] in
                self?.sponsorBlock.loadSegments(
                    videoID: video.videoID,
                    categories: Defaults[.sponsorBlockCategories]
                )

                guard Defaults[.enableReturnYouTubeDislike] else {
                    return
                }

                self?.returnYouTubeDislike.loadDislikes(videoID: video.videoID) { [weak self] dislikes in
                    self?.currentItem?.video?.dislikes = dislikes
                }
            }
        }

        controls.reset()

        backend.playStream(
            stream,
            of: video,
            preservingTime: preservingTime,
            upgrading: upgrading
        )

        if !upgrading {
            updateCurrentArtwork()
        }
    }

    func saveTime(completionHandler: @escaping () -> Void = {}) {
        guard let currentTime = backend.currentTime, currentTime.seconds > 0 else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.preservedTime = currentTime
            completionHandler()
        }
    }

    func upgradeToStream(_ stream: Stream, force: Bool = false) {
        if !self.stream.isNil, force || self.stream != stream {
            playStream(stream, of: currentVideo!, preservingTime: true, upgrading: true)
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

    private func handlePresentationChange() {
        backend.setNeedsDrawing(presentingPlayer)
        controls.hide()

        #if !os(macOS)
            UIApplication.shared.isIdleTimerDisabled = presentingPlayer
        #endif

        if presentingPlayer, closePiPOnOpeningPlayer, playingInPictureInPicture {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.closePiP()
            }
        }

        if !presentingPlayer, pauseOnHidingPlayer, !playingInPictureInPicture {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.pause()
            }
        }

        if !presentingPlayer, !pauseOnHidingPlayer, backend.isPlaying {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.play()
            }
        }
    }

    private func handleNavigationViewPlayerPresentationChange() {
        backend.setNeedsDrawing(playerNavigationLinkActive)
        controls.hide()

        if pauseOnHidingPlayer, !playingInPictureInPicture, !playerNavigationLinkActive {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.pause()
            }
        }
    }

    func changeActiveBackend(from: PlayerBackendType, to: PlayerBackendType) {
        Defaults[.activeBackend] = to
        self.activeBackend = to

        guard var stream = stream else {
            return
        }

        inactiveBackends().forEach { $0.pause() }
        backend.setRate(currentRate)

        let fromBackend: PlayerBackend = from == .appleAVPlayer ? avPlayerBackend : mpvBackend
        let toBackend: PlayerBackend = to == .appleAVPlayer ? avPlayerBackend : mpvBackend

        if let stream = toBackend.stream, toBackend.video == fromBackend.video {
            toBackend.seek(to: fromBackend.currentTime?.seconds ?? .zero) { finished in
                guard finished else {
                    return
                }
                toBackend.play()
            }

            self.stream = stream
            streamSelection = stream

            return
        }

        if !backend.canPlay(stream) {
            guard let preferredStream = preferredStream(availableStreams) else {
                return
            }

            stream = preferredStream
            streamSelection = preferredStream
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.upgradeToStream(stream, force: true)
        }
    }

    private func inactiveBackends() -> [PlayerBackend] {
        [activeBackend == PlayerBackendType.mpv ? avPlayerBackend : mpvBackend]
    }

    func rateLabel(_ rate: Float) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        return "\(formatter.string(from: NSNumber(value: rate))!)×"
    }

    func closeCurrentItem(finished: Bool = false) {
        prepareCurrentItemForHistory(finished: finished)
        currentItem = nil

        backend.closeItem()
    }

    func closePiP() {
        guard playingInPictureInPicture else {
            return
        }

        let wasPlaying = isPlaying
        pause()

        #if os(tvOS)
            show()
        #endif

        backend.closePiP(wasPlaying: wasPlaying)
    }

    func handleCurrentItemChange() {
        #if os(macOS)
            Windows.player.window?.title = windowTitle
        #endif

        Defaults[.lastPlayed] = currentItem
    }

    #if os(macOS)
        var windowTitle: String {
            currentVideo.isNil ? "Not playing" : "\(currentVideo!.title) - \(currentVideo!.author)"
        }
    #else
        func handleEnterForeground() {
            guard closePiPAndOpenPlayerOnEnteringForeground, playingInPictureInPicture else {
                return
            }

            show()
            closePiP()
        }

        func enterFullScreen() {
            guard !controls.playingFullscreen else {
                return
            }

            logger.info("entering fullscreen")

            backend.enterFullScreen()
        }

        func exitFullScreen() {
            guard controls.playingFullscreen else {
                return
            }

            logger.info("exiting fullscreen")

            backend.exitFullScreen()
        }
    #endif

    func updateNowPlayingInfo() {
        guard let video = currentItem?.video else {
            return
        }

        let currentTime = (backend.currentTime?.seconds.isFinite ?? false) ? backend.currentTime!.seconds : 0
        var nowPlayingInfo: [String: AnyObject] = [
            MPMediaItemPropertyTitle: video.title as AnyObject,
            MPMediaItemPropertyArtist: video.author as AnyObject,
            MPNowPlayingInfoPropertyIsLiveStream: video.live as AnyObject,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime as AnyObject,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count as AnyObject,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: 1 as AnyObject,
            MPMediaItemPropertyMediaType: MPMediaType.anyVideo.rawValue as AnyObject
        ]

        if !currentArtwork.isNil {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = currentArtwork as AnyObject
        }

        if !video.live {
            let itemDuration = (backend.playerItemDuration ?? .zero).seconds
            let duration = itemDuration.isFinite ? Double(itemDuration) : nil

            if !duration.isNil {
                nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration as AnyObject
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    func updateCurrentArtwork() {
        guard let video = currentVideo,
              let thumbnailData = try? Data(contentsOf: video.thumbnailURL(quality: .medium)!)
        else {
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

    func toggleFullscreen(_ isFullScreen: Bool) {
        controls.resetTimer()

        #if os(macOS)
            Windows.player.toggleFullScreen()
        #endif

        controls.playingFullscreen = !isFullScreen

        #if os(iOS)
            if controls.playingFullscreen {
                guard !(UIApplication.shared.windows.first?.windowScene?.interfaceOrientation.isLandscape ?? true) else {
                    return
                }
                Orientation.lockOrientation(.landscape, andRotateTo: .landscapeRight)
            } else {
                Orientation.lockOrientation(.allButUpsideDown, andRotateTo: .portrait)
            }
        #endif
    }
}
