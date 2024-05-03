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
    enum PlaybackMode: String, CaseIterable, Defaults.Serializable {
        case queue, shuffle, loopOne, related

        var systemImage: String {
            switch self {
            case .queue:
                return "list.number"
            case .shuffle:
                return "shuffle"
            case .loopOne:
                return "repeat.1"
            case .related:
                return "infinity"
            }
        }

        var description: String {
            switch self {
            case .queue:
                return "Queue"
            case .shuffle:
                return "Queue - shuffled"
            case .loopOne:
                return "Loop one"
            case .related:
                return "Autoplay next"
            }
        }
    }

    static var shared = PlayerModel()

    let logger = Logger(label: "stream.yattee.app")

    var playerItem: AVPlayerItem?

    var mpvPlayerView = MPVPlayerView()

    @Published var presentingPlayer = false { didSet { handlePresentationChange() } }
    @Published var activeBackend = PlayerBackendType.mpv
    @Published var forceBackendOnPlay: PlayerBackendType?

    var avPlayerBackend = AVPlayerBackend()
    var mpvBackend = MPVBackend()
    #if !os(macOS)
        var mpvController = MPVViewController()
    #endif

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

    var previousActiveBackend: PlayerBackendType?

    lazy var playerBackendView = PlayerBackendView()

    @Published var playerSize: CGSize = .zero { didSet {
        #if !os(tvOS)
            #if os(macOS)
                guard videoForDisplay != nil else { return }
            #endif
            backend.setSize(playerSize.width, playerSize.height)
        #endif
    }}
    @Published var aspectRatio = VideoPlayerView.defaultAspectRatio
    @Published var stream: Stream?
    @Published var currentRate: Double = 1.0 { didSet { handleCurrentRateChange() } }

    @Published var qualityProfileSelection: QualityProfile? { didSet { handleQualityProfileChange() } }

    @Published var availableStreams = [Stream]() { didSet { handleAvailableStreamsChange() } }
    @Published var streamSelection: Stream? { didSet { rebuildTVMenu() } }

    @Published var captions: Captions? { didSet {
        mpvBackend.captions = captions
        if let code = captions?.code {
            Defaults[.captionsLanguageCode] = code
        }
    }}

    @Published var queue = [PlayerQueueItem]() { didSet { handleQueueChange() } }
    @Published var currentItem: PlayerQueueItem! { didSet { handleCurrentItemChange() } }
    @Published var videoBeingOpened: Video? { didSet { seek.reset() } }
    @Published var historyVideos = [Video]()
    @Published var preservedTime: CMTime?

    @Published var sponsorBlock = SponsorBlockAPI()
    @Published var segmentRestorationTime: CMTime?
    @Published var lastSkipped: Segment? { didSet { rebuildTVMenu() } }
    @Published var restoredSegments = [Segment]()

    @Published var musicMode = false
    @Published var playbackMode = PlaybackMode.queue { didSet { handlePlaybackModeChange() } }
    @Published var autoplayItem: PlayerQueueItem?
    @Published var autoplayItemSource: Video?
    @Published var advancing = false
    @Published var closing = false

    @Published var returnYouTubeDislike = ReturnYouTubeDislikeAPI()

    @Published var isSeeking = false { didSet {
        backend.setNeedsNetworkStateUpdates(true)
    }}

    #if os(iOS)
        @Published var lockedOrientation: UIInterfaceOrientationMask?
        @Default(.rotateToLandscapeOnEnterFullScreen) private var rotateToLandscapeOnEnterFullScreen
    #endif

    @Published var currentChapterIndex: Int?

    var accounts: AccountsModel { .shared }
    var comments: CommentsModel { .shared }
    var controls: PlayerControlsModel { .shared }
    var playerTime: PlayerTimeModel { .shared }
    var networkState: NetworkStateModel { .shared }
    var seek: SeekModel { .shared }
    var navigation: NavigationModel { .shared }

    var context: NSManagedObjectContext = PersistenceController.shared.container.viewContext
    var backgroundContext = PersistenceController.shared.container.newBackgroundContext()

    #if os(tvOS)
        static let fullScreenIsDefault = true
    #else
        static let fullScreenIsDefault = false
    #endif
    @Published var playingFullScreen = PlayerModel.fullScreenIsDefault

    @Published var playingInPictureInPicture = false
    var pipController: AVPictureInPictureController?
    var pipDelegate = PiPDelegate()
    #if !os(macOS)
        var appleAVPlayerViewControllerDelegate = AppleAVPlayerViewControllerDelegate()
    #endif

    var playerError: Error? { didSet {
        if let error = playerError {
            navigation.presentAlert(title: "Failed loading video".localized(), message: error.localizedDescription)
        }
    }}

    @Default(.saveHistory) var saveHistory
    @Default(.saveLastPlayed) var saveLastPlayed
    @Default(.lastPlayed) var lastPlayed
    @Default(.qualityProfiles) var qualityProfiles
    @Default(.avPlayerUsesSystemControls) var avPlayerUsesSystemControls
    @Default(.forceAVPlayerForLiveStreams) var forceAVPlayerForLiveStreams
    @Default(.pauseOnHidingPlayer) private var pauseOnHidingPlayer
    @Default(.closePiPOnNavigation) var closePiPOnNavigation
    @Default(.closePiPOnOpeningPlayer) var closePiPOnOpeningPlayer
    @Default(.resetWatchedStatusOnPlaying) var resetWatchedStatusOnPlaying
    @Default(.playerRate) var playerRate
    @Default(.systemControlsSeekDuration) var systemControlsSeekDuration

    #if os(macOS)
        @Default(.buttonBackwardSeekDuration) private var buttonBackwardSeekDuration
        @Default(.buttonForwardSeekDuration) private var buttonForwardSeekDuration
    #endif

    #if !os(macOS)
        @Default(.closePiPAndOpenPlayerOnEnteringForeground) var closePiPAndOpenPlayerOnEnteringForeground
    #endif

    private var currentArtwork: MPMediaItemArtwork?

    var onPresentPlayer = [() -> Void]()
    var onPlayStream = [(Stream) -> Void]()
    var rateToRestore: Float?
    private var remoteCommandCenterConfigured = false

    #if os(macOS)
        var keyPressMonitor: Any?
    #endif

    init() {
        #if !os(macOS)
            mpvBackend.controller = mpvController
            mpvBackend.client = mpvController.client
        #endif

        playbackMode = Defaults[.playbackMode]

        guard pipController.isNil else { return }

        pipController = .init(playerLayer: avPlayerBackend.playerLayer)
        pipController?.delegate = pipDelegate
        #if os(iOS)
            if #available(iOS 14.2, *) {
                pipController?.canStartPictureInPictureAutomaticallyFromInline = true
            }
        #endif
        currentRate = playerRate
    }

    func show() {
        #if os(macOS)
            if presentingPlayer {
                Windows.player.focus()
                assignKeyPressMonitor()
                return
            }
        #endif

        #if os(iOS)
            Delay.by(0.5) {
                self.navigation.hideKeyboard()
            }
        #endif

        presentingPlayer = true

        #if os(macOS)
            Windows.player.open()
            Windows.player.focus()
            assignKeyPressMonitor()
        #endif
    }

    func hide(animate: Bool = true) {
        if animate {
            withAnimation(.easeOut(duration: 0.2)) {
                presentingPlayer = false
            }
        } else {
            presentingPlayer = false
        }

        DispatchQueue.main.async { [weak self] in
            Delay.by(0.3) {
                self?.exitFullScreen(showControls: false)
            }
        }

        #if os(macOS)
            destroyKeyPressMonitor()
            Windows.player.hide()
        #endif
    }

    func togglePlayer() {
        #if os(macOS)
            if !presentingPlayer {
                Windows.player.open()
            }
            Windows.player.focus()

            if Windows.player.visible,
               closePiPOnOpeningPlayer
            {
                closePiP()
            }

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

    var isPaused: Bool {
        backend.isPaused
    }

    var hasStarted: Bool {
        backend.hasStarted
    }

    var playerItemDuration: CMTime? {
        guard !currentItem.isNil else {
            return nil
        }

        return backend.playerItemDuration
    }

    var playerItemDurationWithoutSponsorSegments: CMTime? {
        PlayerTimeModel.shared.duration - .secondsInDefaultTimescale(
            sponsorBlock.segments.reduce(0) { $0 + $1.duration }
        )
    }

    var videoDuration: TimeInterval? {
        playerItemDuration?.seconds ?? currentItem?.duration ?? currentVideo?.length
    }

    var time: CMTime? {
        currentItem?.playbackTime
    }

    var live: Bool {
        currentVideo?.live ?? false
    }

    var playingLive: Bool {
        guard live,
              let videoDuration,
              let time = backend.currentTime?.seconds else { return false }

        return videoDuration - time < 30
    }

    var liveStreamInAVPlayer: Bool {
        live && activeBackend == .appleAVPlayer
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

    func play(_ video: Video, at time: CMTime? = nil, showingPlayer: Bool = true) {
        pause()
        videoBeingOpened = video

        navigation.presentingChannelSheet = false

        var changeBackendHandler: (() -> Void)?

        if let backend = (live && forceAVPlayerForLiveStreams) ? PlayerBackendType.appleAVPlayer :
            (qualityProfile?.backend ?? QualityProfilesModel.shared.automaticProfile?.backend),
            activeBackend != backend,
            backend == .appleAVPlayer || !avPlayerBackend.startPictureInPictureOnPlay
        {
            changeBackendHandler = { [weak self] in
                guard let self else { return }
                self.changeActiveBackend(from: self.activeBackend, to: backend)
            }
        }

        #if os(iOS)
            if !playingInPictureInPicture, showingPlayer {
                onPresentPlayer.append { [weak self] in
                    changeBackendHandler?()
                    self?.playNow(video, at: time)
                }
                show()
                return
            }
        #endif

        changeBackendHandler?()
        playNow(video, at: time)

        guard !playingInPictureInPicture else {
            return
        }

        if showingPlayer {
            show()
        }
    }

    func playStream(
        _ stream: Stream,
        of video: Video,
        preservingTime: Bool = false,
        upgrading: Bool = false,
        withBackend: PlayerBackend? = nil
    ) {
        playerError = nil
        if !upgrading, !video.isLocal {
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

        if video.isLocal {
            resetSegments()
        }

        (withBackend ?? backend).playStream(
            stream,
            of: video,
            preservingTime: preservingTime,
            upgrading: upgrading
        )

        DispatchQueue.main.async {
            self.forceBackendOnPlay = nil
        }

        if !upgrading {
            updateCurrentArtwork()
        }
    }

    func saveTime(completionHandler: @escaping () -> Void = {}) {
        guard let currentTime = backend.currentTime, currentTime.seconds > 0 else {
            completionHandler()
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.preservedTime = currentTime
            completionHandler()
        }
    }

    func upgradeToStream(_ stream: Stream, force: Bool = false) {
        guard let video = currentVideo else {
            return
        }

        if !self.stream.isNil, force || self.stream != stream {
            playStream(stream, of: video, preservingTime: true, upgrading: true)
        }
    }

    private func handleAvailableStreamsChange() {
        rebuildTVMenu()

        guard stream.isNil else {
            return
        }

        if let backend = forceBackendOnPlay ?? ((live && forceAVPlayerForLiveStreams) ? PlayerBackendType.appleAVPlayer : qualityProfile?.backend),
           backend != activeBackend,
           backend == .appleAVPlayer || !(avPlayerBackend.startPictureInPictureOnPlay || playingInPictureInPicture)
        {
            changeActiveBackend(from: activeBackend, to: backend)
        }

        let localStream = (availableStreams.count == 1 && availableStreams.first!.isLocal) ? availableStreams.first : nil

        guard let stream = localStream ?? streamByQualityProfile,
              let currentVideo
        else {
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async {
                self.streamSelection = stream
            }
            self.playStream(
                stream,
                of: currentVideo,
                preservingTime: !self.currentItem.playbackTime.isNil
            )
        }
    }

    private func handlePresentationChange() {
        backend.setNeedsDrawing(presentingPlayer)

        #if os(iOS)
            if presentingPlayer, activeBackend == .appleAVPlayer, avPlayerUsesSystemControls, Constants.isIPhone {
                Orientation.lockOrientation(.all, andRotateTo: .portrait)
            }
        #endif

        controls.hide()
        controls.hideOverlays()

        #if !os(macOS)
            UIApplication.shared.isIdleTimerDisabled = presentingPlayer
        #endif

        if presentingPlayer, closePiPOnOpeningPlayer, playingInPictureInPicture {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.closePiP()
            }
        }

        if !presentingPlayer, pauseOnHidingPlayer, !playingInPictureInPicture {
            DispatchQueue.main.async { [weak self] in
                self?.pause()
            }
        }

        if !presentingPlayer {
            #if os(iOS)
                if Defaults[.lockPortraitWhenBrowsing] {
                    Orientation.lockOrientation(.all, andRotateTo: .portrait)
                } else {
                    Orientation.lockOrientation(.allButUpsideDown)
                }

                OrientationModel.shared.stopOrientationUpdates()
            #endif
        }
    }

    func changeActiveBackend(from: PlayerBackendType, to: PlayerBackendType, changingStream: Bool = true, isInClosePip: Bool = false) {
        guard activeBackend != to else {
            return
        }

        logger.info("changing backend from \(from.rawValue) to \(to.rawValue)")

        let wasPlaying = isPlaying

        if to == .mpv && !isInClosePip {
            closePiP()
        }

        Defaults[.activeBackend] = to
        self.activeBackend = to

        let fromBackend: PlayerBackend = from == .appleAVPlayer ? avPlayerBackend : mpvBackend
        let toBackend: PlayerBackend = to == .appleAVPlayer ? avPlayerBackend : mpvBackend

        toBackend.cancelLoads()
        fromBackend.cancelLoads()

        if !self.backend.canPlayAtRate(currentRate) {
            currentRate = self.backend.suggestedPlaybackRates.last { $0 < currentRate } ?? 1.0
        }

        self.rateToRestore = Float(currentRate)

        self.backend.didChangeTo()

        if wasPlaying {
            fromBackend.pause()
        }

        guard var stream, changingStream else {
            return
        }

        if let stream = toBackend.stream, toBackend.video == fromBackend.video {
            toBackend.seek(to: fromBackend.currentTime?.seconds ?? .zero, seekType: .backendSync) { finished in
                guard finished else {
                    return
                }
                if wasPlaying {
                    toBackend.play()
                }
            }

            self.stream = stream
            streamSelection = stream

            self.upgradeToStream(stream, force: true)

            return
        }

        if !backend.canPlay(stream) ||
            (to == .mpv && stream.isHLS) ||
            (to == .appleAVPlayer && !stream.isHLS)
        {
            guard let preferredStream = streamByQualityProfile else {
                return
            }

            stream = preferredStream
            streamSelection = preferredStream
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else {
                return
            }
            self.upgradeToStream(stream, force: true)
        }
    }

    func handleCurrentRateChange() {
        backend.setRate(currentRate)
        playerRate = currentRate
    }

    func handleQualityProfileChange() {
        guard let profile = qualityProfile else { return }

        if activeBackend != profile.backend { changeActiveBackend(from: activeBackend, to: profile.backend) }
        guard let profileStream = streamByQualityProfile, stream != profileStream else { return }

        DispatchQueue.main.async { [weak self] in
            self?.streamSelection = profileStream
            self?.upgradeToStream(profileStream)
        }
    }

    func rateLabel(_ rate: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        return "\(formatter.string(from: NSNumber(value: rate))!)×"
    }

    func closeCurrentItem(finished: Bool = false) {
        pause()
        videoBeingOpened = nil
        advancing = false
        forceBackendOnPlay = nil

        closing = true
        controls.presentingControls = false

        self.prepareCurrentItemForHistory(finished: finished)

        self.hide()

        Delay.by(0.8) { [weak self] in
            guard let self else { return }
            self.closePiP()

            withAnimation {
                self.currentItem = nil
            }
            self.updateNowPlayingInfo()

            self.backend.closeItem()
            self.aspectRatio = VideoPlayerView.defaultAspectRatio
            self.resetAutoplay()
            self.closing = false
            self.playingFullScreen = false
        }
    }

    func startPiP() {
        previousActiveBackend = activeBackend
        avPlayerBackend.startPictureInPictureOnPlay = false
        avPlayerBackend.startPictureInPictureOnSwitch = false

        if activeBackend == .appleAVPlayer {
            avPlayerBackend.tryStartingPictureInPicture()
            return
        }

        // First, we need to create an array with supported formats.
        let formatOrderPiP: [QualityProfile.Format] = [.hls, .stream, .mp4]

        guard let video = currentVideo else { return }
        guard let stream = avPlayerBackend.bestPlayable(availableStreams, maxResolution: .hd720p30, formatOrder: formatOrderPiP) else { return }

        if avPlayerBackend.video == video {
            if activeBackend != .appleAVPlayer {
                avPlayerBackend.startPictureInPictureOnSwitch = true
            }
            changeActiveBackend(from: activeBackend, to: .appleAVPlayer)
        } else {
            avPlayerBackend.startPictureInPictureOnPlay = true
            playStream(stream, of: video, preservingTime: true, upgrading: true, withBackend: avPlayerBackend)
        }

        var retryCount = 0
        _ = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            if let pipController = self?.pipController, pipController.isPictureInPictureActive, self?.avPlayerBackend.isPlaying == true {
                self?.exitFullScreen()
                self?.controls.objectWillChange.send()
                timer.invalidate()
            } else if retryCount < 3, self?.activeBackend == .appleAVPlayer, self?.avPlayerBackend.startPictureInPictureOnSwitch == false {
                // If PiP didn't start, try starting it again up to 3 times,
                self?.avPlayerBackend.startPictureInPictureOnSwitch = true
                self?.avPlayerBackend.tryStartingPictureInPicture()
                retryCount += 1
            }
        }
    }

    var transitioningToPiP: Bool {
        avPlayerBackend.startPictureInPictureOnPlay || avPlayerBackend.startPictureInPictureOnSwitch
    }

    var pipPossible: Bool {
        guard activeBackend == .appleAVPlayer else { return !transitioningToPiP }

        guard let pipController else { return false }
        guard !pipController.isPictureInPictureActive else { return true }

        return pipController.isPictureInPicturePossible && !transitioningToPiP
    }

    func closePiP() {
        guard playingInPictureInPicture else {
            return
        }

        avPlayerBackend.startPictureInPictureOnPlay = false
        avPlayerBackend.startPictureInPictureOnSwitch = false

        #if os(tvOS)
            show()
        #endif

        if previousActiveBackend == .mpv {
            saveTime {
                self.changeActiveBackend(from: self.activeBackend, to: .mpv, isInClosePip: true)
                _ = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
                    if self?.activeBackend == .mpv, self?.mpvBackend.isPlaying == true {
                        self?.backend.closePiP()
                        self?.controls.resetTimer()
                        timer.invalidate()
                    }
                }
            }
        } else {
            backend.closePiP()
        }
    }

    var pipImage: String {
        transitioningToPiP ? "pip.fill" : pipController?.isPictureInPictureActive ?? false ? "pip.exit" : "pip.enter"
    }

    var fullscreenImage: String {
        playingFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
    }

    func toggleFullScreenAction() {
        toggleFullscreen(playingFullScreen, showControls: false)
    }

    func togglePiPAction() {
        if pipController?.isPictureInPictureActive ?? false {
            closePiP()
        } else {
            startPiP()
        }
    }

    #if os(iOS)
        var lockOrientationImage: String {
            lockedOrientation.isNil ? "lock.rotation.open" : "lock.rotation"
        }

        func lockOrientationAction() {
            if lockedOrientation.isNil {
                let orientationMask = OrientationTracker.shared.currentInterfaceOrientationMask
                lockedOrientation = orientationMask
                let orientation = OrientationTracker.shared.currentInterfaceOrientation
                Orientation.lockOrientation(orientationMask, andRotateTo: .landscapeLeft)
                // iOS 16 workaround
                Orientation.lockOrientation(orientationMask, andRotateTo: orientation)
            } else {
                lockedOrientation = nil
                Orientation.lockOrientation(.allButUpsideDown, andRotateTo: OrientationTracker.shared.currentInterfaceOrientation)
            }
        }
    #endif

    func replayAction() {
        backend.seek(to: 0.0, seekType: .userInteracted)
    }

    func handleQueueChange() {
        Defaults[.queue] = queue

        updateRemoteCommandCenter()
        controls.objectWillChange.send()
    }

    func handleCurrentItemChange() {
        if currentItem == nil {
            FeedModel.shared.calculateUnwatchedFeed()
        }

        // Captions need to be set to nil on item change, to clear the previus values.
        captions = nil

        #if os(macOS)
            Windows.player.window?.title = windowTitle
        #endif

        DispatchQueue.main.async(qos: .background) { [weak self] in
            guard let self else { return }
            if self.saveLastPlayed {
                self.lastPlayed = self.currentItem
            }

            if self.playbackMode == .related,
               let video = self.currentVideo,
               self.autoplayItemSource.isNil || self.autoplayItemSource?.videoID != video.videoID
            {
                self.setRelatedAutoplayItem()
            }
        }
    }

    func handlePlaybackModeChange() {
        Defaults[.playbackMode] = playbackMode

        updateRemoteCommandCenter()

        guard playbackMode == .related else {
            autoplayItem = nil
            return
        }
        setRelatedAutoplayItem()
    }

    func setRelatedAutoplayItem() {
        guard let video = currentVideo else { return }
        let related = video.related.filter { $0.videoID != autoplayItem?.video?.videoID }

        let watchFetchRequest = Watch.fetchRequest()
        watchFetchRequest.predicate = NSPredicate(format: "videoID IN %@", related.map(\.videoID) as [String])

        let results = try? context.fetch(watchFetchRequest)

        context.perform { [weak self] in
            guard let self,
                  let results else { return }
            let resultsIds = results.map(\.videoID)

            guard let autoplayVideo = related.filter({ !resultsIds.contains($0.videoID) }).randomElement() else {
                return
            }

            let item = PlayerQueueItem(autoplayVideo)
            self.autoplayItem = item
            self.autoplayItemSource = video

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                self.playerAPI(item.video)?.loadDetails(item, failureHandler: nil) { newItem in
                    guard newItem.videoID == self.autoplayItem?.videoID else { return }
                    self.autoplayItem = newItem
                    self.updateRemoteCommandCenter()
                    self.controls.objectWillChange.send()
                }
            }
        }
    }

    func updateRemoteCommandCenter() {
        let skipForwardCommand = MPRemoteCommandCenter.shared().skipForwardCommand
        let skipBackwardCommand = MPRemoteCommandCenter.shared().skipBackwardCommand
        let previousTrackCommand = MPRemoteCommandCenter.shared().previousTrackCommand
        let nextTrackCommand = MPRemoteCommandCenter.shared().nextTrackCommand

        if !remoteCommandCenterConfigured {
            remoteCommandCenterConfigured = true

            #if !os(macOS)
                try? AVAudioSession.sharedInstance().setCategory(
                    .playback,
                    mode: .moviePlayback
                )

                UIApplication.shared.beginReceivingRemoteControlEvents()
            #endif

            let interval = TimeInterval(systemControlsSeekDuration) ?? 10
            let preferredIntervals = [NSNumber(value: interval)]

            skipForwardCommand.preferredIntervals = preferredIntervals
            skipBackwardCommand.preferredIntervals = preferredIntervals

            skipForwardCommand.addTarget { [weak self] _ in
                self?.backend.seek(relative: .secondsInDefaultTimescale(interval), seekType: .userInteracted)
                return .success
            }

            skipBackwardCommand.addTarget { [weak self] _ in
                self?.backend.seek(relative: .secondsInDefaultTimescale(-interval), seekType: .userInteracted)
                return .success
            }

            previousTrackCommand.addTarget { [weak self] _ in
                self?.backend.seek(to: .zero, seekType: .userInteracted)
                return .success
            }

            nextTrackCommand.addTarget { [weak self] _ in
                self?.advanceToNextItem()
                return .success
            }

            MPRemoteCommandCenter.shared().playCommand.addTarget { [weak self] _ in
                self?.play()
                return .success
            }

            MPRemoteCommandCenter.shared().pauseCommand.addTarget { [weak self] _ in
                self?.pause()
                return .success
            }

            MPRemoteCommandCenter.shared().togglePlayPauseCommand.addTarget { [weak self] _ in
                self?.togglePlay()
                return .success
            }

            MPRemoteCommandCenter.shared().changePlaybackPositionCommand.addTarget { [weak self] remoteEvent in
                guard let event = remoteEvent as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }

                self?.backend.seek(to: event.positionTime, seekType: .userInteracted)

                return .success
            }
        }

        switch Defaults[.systemControlsCommands] {
        case .seek:
            previousTrackCommand.isEnabled = false
            nextTrackCommand.isEnabled = false
            skipForwardCommand.isEnabled = true
            skipBackwardCommand.isEnabled = true

        case .restartAndAdvanceToNext:
            skipForwardCommand.isEnabled = false
            skipBackwardCommand.isEnabled = false
            previousTrackCommand.isEnabled = true
            nextTrackCommand.isEnabled = isAdvanceToNextItemAvailable
        }
    }

    func resetAutoplay() {
        autoplayItem = nil
        autoplayItemSource = nil
    }

    #if os(macOS)
        var windowTitle: String {
            currentVideo.isNil ? "Not Playing" : "\(currentVideo!.displayTitle) - \(currentVideo!.displayAuthor)"
        }
    #else
        func handleEnterForeground() {
            setNeedsDrawing(presentingPlayer)

            if !musicMode, activeBackend == .appleAVPlayer {
                avPlayerBackend.bindPlayerToLayer()
            }

            guard closePiPAndOpenPlayerOnEnteringForeground, playingInPictureInPicture else {
                return
            }

            show()
            closePiP()
        }

        func handleEnterBackground() {
            if Defaults[.pauseOnEnteringBackground], !playingInPictureInPicture, !musicMode {
                pause()
            } else if !playingInPictureInPicture {
                avPlayerBackend.removePlayerFromLayer()
            }
        }
    #endif

    func enterFullScreen(showControls: Bool = true) {
        guard !playingFullScreen else { return }

        logger.info("entering fullscreen")
        toggleFullscreen(false, showControls: showControls)
    }

    func exitFullScreen(showControls: Bool = true) {
        guard playingFullScreen else { return }

        logger.info("exiting fullscreen")
        toggleFullscreen(true, showControls: showControls)
    }

    func updateNowPlayingInfo() {
        #if os(tvOS)
            guard activeBackend == .mpv else { return }
        #endif

        #if os(iOS)
            if activeBackend == .appleAVPlayer, avPlayerUsesSystemControls {
                return
            }
        #endif

        guard let video = currentItem?.video else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = .none
            return
        }

        let currentTime = (backend.currentTime?.seconds.isFinite ?? false) ? backend.currentTime!.seconds : 0
        var nowPlayingInfo: [String: AnyObject] = [
            MPMediaItemPropertyTitle: video.displayTitle as AnyObject,
            MPMediaItemPropertyArtist: video.displayAuthor as AnyObject,
            MPNowPlayingInfoPropertyIsLiveStream: live as AnyObject,
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
              let thumbnailURL = video.thumbnailURL(quality: .medium)
        else {
            return
        }

        let task = URLSession.shared.dataTask(with: thumbnailURL) { [weak self] thumbnailData, _, _ in
            guard let thumbnailData else {
                return
            }

            #if os(macOS)
                guard let image = NSImage(data: thumbnailData) else { return }
            #else
                guard let image = UIImage(data: thumbnailData) else { return }
            #endif

            self?.currentArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        task.resume()
    }

    func toggleFullscreen(_ isFullScreen: Bool, showControls: Bool = true) {
        controls.presentingControls = showControls && isFullScreen

        #if os(macOS)
            Windows.player.toggleFullScreen()
        #endif

        playingFullScreen = !isFullScreen

        #if os(iOS)
            if playingFullScreen {
                if activeBackend == .appleAVPlayer, avPlayerUsesSystemControls {
                    avPlayerBackend.controller.enterFullScreen(animated: true)
                    return
                }
                guard rotateToLandscapeOnEnterFullScreen.isRotating else { return }
                if currentVideoIsLandscape {
                    let delay = activeBackend == .appleAVPlayer && avPlayerUsesSystemControls ? 0.8 : 0
                    Delay.by(delay) {
                        let orientation = OrientationTracker.shared.currentDeviceOrientation.isLandscape ? OrientationTracker.shared.currentInterfaceOrientation : self.rotateToLandscapeOnEnterFullScreen.interfaceOrientationSetting

                        Orientation.lockOrientation(.allButUpsideDown, andRotateTo: orientation)
                    }
                }
            } else {
                if activeBackend == .appleAVPlayer, avPlayerUsesSystemControls {
                    avPlayerBackend.controller.exitFullScreen(animated: true)
                    avPlayerBackend.controller.dismiss(animated: true)
                    return
                }
                let rotationOrientation = Constants.isIPhone ? UIInterfaceOrientation.portrait : nil
                Orientation.lockOrientation(.allButUpsideDown, andRotateTo: rotationOrientation)
            }

        #endif
    }

    func setNeedsDrawing(_ needsDrawing: Bool) {
        backends.forEach { $0.setNeedsDrawing(needsDrawing) }
    }

    func toggleMusicMode() {
        musicMode.toggle()

        if musicMode {
            aspectRatio = VideoPlayerView.defaultAspectRatio
            controls.presentingControls = true
            controls.removeTimer()

            backend.startMusicMode()
        } else {
            backend.stopMusicMode()
            Delay.by(0.25) {
                self.updateAspectRatio()
            }

            controls.resetTimer()
        }
    }

    func updateAspectRatio() {
        #if !os(tvOS)
            guard aspectRatio != backend.aspectRatio else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                withAnimation {
                    self.aspectRatio = self.backend.aspectRatio
                }
            }
        #endif
    }

    var currentVideoIsLandscape: Bool {
        guard currentVideo != nil else { return false }

        return aspectRatio > 1
    }

    var formattedSize: String {
        guard let videoWidth = backend?.videoWidth, let videoHeight = backend?.videoHeight else { return "unknown" }
        return "\(String(format: "%.2f", videoWidth))\u{d7}\(String(format: "%.2f", videoHeight))"
    }

    func handleOnPlayStream(_ stream: Stream) {
        backend.setRate(currentRate)

        onPlayStream.forEach { $0(stream) }
        onPlayStream.removeAll()
    }

    func updateTime(_ cmTime: CMTime) {
        let time = CMTimeGetSeconds(cmTime)
        let newChapterIndex = chapterForTime(time)
        if currentChapterIndex != newChapterIndex {
            DispatchQueue.main.async {
                self.currentChapterIndex = newChapterIndex
            }
        }
    }

    private func chapterForTime(_ time: Double) -> Int? {
        guard let chapters = self.videoForDisplay?.chapters else {
            return nil
        }

        for (index, chapter) in chapters.enumerated() {
            let nextChapterStartTime = index < (chapters.count - 1) ? chapters[index + 1].start : nil

            if let nextChapterStart = nextChapterStartTime {
                if time >= chapter.start, time < nextChapterStart {
                    return index
                }
            } else {
                if time >= chapter.start {
                    return index
                }
            }
        }

        return nil
    }

    #if os(macOS)
        private func assignKeyPressMonitor() {
            keyPressMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { keyEvent -> NSEvent? in
                switch keyEvent.keyCode {
                case 124:
                    if !self.liveStreamInAVPlayer {
                        let interval = TimeInterval(self.buttonForwardSeekDuration) ?? 10
                        self.backend.seek(
                            relative: .secondsInDefaultTimescale(interval),
                            seekType: .userInteracted
                        )
                    }
                case 123:
                    if !self.liveStreamInAVPlayer {
                        let interval = TimeInterval(self.buttonBackwardSeekDuration) ?? 10
                        self.backend.seek(
                            relative: .secondsInDefaultTimescale(-interval),
                            seekType: .userInteracted
                        )
                    }
                case 3:
                    self.toggleFullscreen(
                        self.playingFullScreen,
                        showControls: false
                    )
                case 49:
                    if !self.controls.isLoadingVideo {
                        self.backend.togglePlay()
                    }
                default:
                    return keyEvent
                }
                return nil
            }
        }

        private func destroyKeyPressMonitor() {
            if let keyPressMonitor = keyPressMonitor {
                NSEvent.removeMonitor(keyPressMonitor)
            }
        }
    #endif
}
