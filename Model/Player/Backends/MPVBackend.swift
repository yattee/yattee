import AVFAudio
import CoreMedia
import Defaults
import Foundation
import Libmpv
import Logging
import MediaPlayer
import Repeat
import SwiftUI

final class MPVBackend: PlayerBackend {
    static var timeUpdateInterval = 0.5
    static var networkStateUpdateInterval = 0.1
    static var refreshRateUpdateInterval = 0.5

    private var logger = Logger(label: "mpv-backend")

    var model: PlayerModel { .shared }
    var controls: PlayerControlsModel { .shared }
    var playerTime: PlayerTimeModel { .shared }
    var networkState: NetworkStateModel { .shared }
    var seek: SeekModel { .shared }

    var stream: Stream?
    var video: Video?
    var captions: Captions? {
        didSet {
            Task {
                await handleCaptionsChange()
            }
        }
    }

    var currentTime: CMTime?

    var loadedVideo = false
    var isLoadingVideo = true { didSet {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.controls.isLoadingVideo = self.isLoadingVideo
            self.setNeedsNetworkStateUpdates(true)
            self.model.objectWillChange.send()
        }
    }}

    var hasStarted = false
    var isPaused = false
    var isPlaying = true { didSet {
        networkStateTimer.start()

        if isPlaying {
            startClientUpdates()
        } else {
            stopControlsUpdates()
        }

        updateControlsIsPlaying()

        #if os(macOS)
            if isPlaying {
                ScreenSaverManager.shared.disable(reason: "Yattee is playing video")
            } else {
                ScreenSaverManager.shared.enable()
            }

            MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        #else
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = self.model.presentingPlayer && self.isPlaying
            }
        #endif
    }}
    var isSeeking = false {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.model.isSeeking = self.isSeeking
            }
        }
    }

    var playerItemDuration: CMTime?

    #if !os(macOS)
        var controller: MPVViewController!
    #endif
    var client: MPVClient! { didSet { client.backend = self } }

    private var clientTimer: Repeater!
    private var networkStateTimer: Repeater!
    private var refreshRateTimer: Repeater!

    private var onFileLoaded: (() -> Void)?

    var controlsUpdates = false
    private var timeObserverThrottle = Throttle(interval: 2)

    var suggestedPlaybackRates: [Double] {
        [0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 1.75, 2, 3, 4]
    }

    func canPlayAtRate(_ rate: Double) -> Bool {
        rate > 0 && rate <= 100
    }

    var tracks: Int {
        client?.tracksCount ?? -1
    }

    var aspectRatio: Double {
        client?.aspectRatio ?? VideoPlayerView.defaultAspectRatio
    }

    var frameDropCount: Int {
        client?.frameDropCount ?? 0
    }

    var outputFps: Double {
        client?.outputFps ?? 0
    }

    var formattedOutputFps: String {
        String(format: "%.2ffps", outputFps)
    }

    var hwDecoder: String {
        client?.hwDecoder ?? "unknown"
    }

    var bufferingState: Double {
        client?.bufferingState ?? 0
    }

    var cacheDuration: Double {
        client?.cacheDuration ?? 0
    }

    var videoFormat: String {
        client?.videoFormat ?? "unknown"
    }

    var videoCodec: String {
        client?.videoCodec ?? "unknown"
    }

    var currentVo: String {
        client?.currentVo ?? "unknown"
    }

    var videoWidth: Double? {
        if let width = client?.width, width != "unknown" {
            return Double(width)
        }

        return nil
    }

    var videoHeight: Double? {
        if let height = client?.height, height != "unknown" {
            return Double(height)
        }

        return nil
    }

    var audioFormat: String {
        client?.audioFormat ?? "unknown"
    }

    var audioCodec: String {
        client?.audioCodec ?? "unknown"
    }

    var currentAo: String {
        client?.currentAo ?? "unknown"
    }

    var audioChannels: String {
        client?.audioChannels ?? "unknown"
    }

    var audioSampleRate: String {
        client?.audioSampleRate ?? "unknown"
    }

    init() {
        clientTimer = .init(interval: .seconds(Self.timeUpdateInterval), mode: .infinite) { [weak self] _ in
            guard let self, self.model.activeBackend == .mpv else {
                return
            }
            self.getTimeUpdates()
        }

        networkStateTimer = .init(interval: .seconds(Self.networkStateUpdateInterval), mode: .infinite) { [weak self] _ in
            guard let self, self.model.activeBackend == .mpv else {
                return
            }
            self.updateNetworkState()
        }

        refreshRateTimer = .init(interval: .seconds(Self.refreshRateUpdateInterval), mode: .infinite) { [weak self] _ in
            guard let self, self.model.activeBackend == .mpv else { return }
            self.checkAndUpdateRefreshRate()
        }
    }

    typealias AreInIncreasingOrder = (Stream, Stream) -> Bool

    func canPlay(_ stream: Stream) -> Bool {
        stream.format != .av1
    }

    func playStream(_ stream: Stream, of video: Video, preservingTime: Bool, upgrading: Bool) {
        #if !os(macOS)
            if model.presentingPlayer {
                DispatchQueue.main.async {
                    UIApplication.shared.isIdleTimerDisabled = true
                }
            }
        #endif

        var captions: Captions?

        if Defaults[.captionsAutoShow] == true {
            let captionsDefaultLanguageCode = Defaults[.captionsDefaultLanguageCode],
                captionsFallbackLanguageCode = Defaults[.captionsFallbackLanguageCode]

            // Try to get captions with the default language code first
            captions = video.captions.first { $0.code == captionsDefaultLanguageCode } ??
                video.captions.first { $0.code.contains(captionsDefaultLanguageCode) }

            // If there are still no captions, try to get captions with the fallback language code
            if captions.isNil && !captionsFallbackLanguageCode.isEmpty {
                captions = video.captions.first { $0.code == captionsFallbackLanguageCode } ??
                    video.captions.first { $0.code.contains(captionsFallbackLanguageCode) }
            }
        } else {
            captions = nil
        }

        let updateCurrentStream = {
            DispatchQueue.main.async { [weak self] in
                self?.stream = stream
                self?.video = video
                self?.model.stream = stream
                self?.captions = captions
            }
        }

        let startPlaying = {
            #if !os(macOS)
                self.model.setAudioSessionActive(true)
            #endif

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.startClientUpdates()

                if Defaults[.captionsAutoShow] { self.client?.setSubToAuto() } else { self.client?.setSubToNo() }
                PlayerModel.shared.captions = self.captions

                if !preservingTime,
                   !upgrading,
                   let segment = self.model.sponsorBlock.segments.first,
                   self.model.lastSkipped.isNil
                {
                    self.seek(to: segment.endTime, seekType: .segmentSkip(segment.category)) { finished in
                        guard finished else {
                            return
                        }

                        self.model.lastSkipped = segment
                        self.play()
                        self.model.handleOnPlayStream(stream)
                    }
                } else {
                    self.play()
                    self.model.handleOnPlayStream(stream)
                }
            }
        }

        let replaceItem: (CMTime?) -> Void = { [weak self] time in
            guard let self else {
                return
            }

            self.stop()

            DispatchQueue.main.async { [weak self] in
                guard let self, let client = self.client else {
                    return
                }

                if let url = stream.singleAssetURL {
                    self.onFileLoaded = {
                        updateCurrentStream()
                        startPlaying()
                    }

                    if video.isLocal, video.localStreamIsFile {
                        if url.startAccessingSecurityScopedResource() {
                            URLBookmarkModel.shared.saveBookmark(url)
                        }
                    }

                    client.loadFile(url, bitrate: stream.bitrate, kind: stream.kind, sub: captions?.url, time: time, forceSeekable: stream.kind == .hls) { [weak self] _ in
                        self?.isLoadingVideo = true
                    }
                } else {
                    self.onFileLoaded = {
                        updateCurrentStream()
                        startPlaying()
                    }

                    let fileToLoad = self.model.musicMode ? stream.audioAsset.url : stream.videoAsset.url
                    let audioTrack = self.model.musicMode ? nil : stream.audioAsset.url

                    client.loadFile(fileToLoad, audio: audioTrack, bitrate: stream.bitrate, kind: stream.kind, sub: captions?.url, time: time, forceSeekable: stream.kind == .hls) { [weak self] _ in
                        self?.isLoadingVideo = true
                        self?.pause()
                    }
                }
            }
        }

        if preservingTime {
            if model.preservedTime.isNil || upgrading {
                model.saveTime {
                    replaceItem(self.model.preservedTime)
                }
            } else {
                replaceItem(self.model.preservedTime)
            }
        } else {
            replaceItem(nil)
        }

        startClientUpdates()
    }

    func startRefreshRateUpdates() {
        refreshRateTimer.start()
    }

    func stopRefreshRateUpdates() {
        refreshRateTimer.pause()
    }

    func play() {
        #if !os(macOS)
            model.setAudioSessionActive(true)
        #endif
        startClientUpdates()
        startRefreshRateUpdates()

        if controls.presentingControls {
            startControlsUpdates()
        }

        setRate(model.currentRate)

        // After the video has ended, hitting play restarts the video from the beginning.
        if let currentTime, currentTime.seconds.formattedAsPlaybackTime() == model.playerTime.duration.seconds.formattedAsPlaybackTime() &&
            currentTime.seconds > 0 && model.playerTime.duration.seconds > 0
        {
            seek(to: 0, seekType: .loopRestart)
        }

        client?.play()

        isPlaying = true
        isPaused = false

        // Setting hasStarted to true the first time player started
        if !hasStarted {
            hasStarted = true
        }
    }

    func pause() {
        #if !os(macOS)
            model.setAudioSessionActive(false)
        #endif
        stopClientUpdates()
        stopRefreshRateUpdates()

        client?.pause()
        isPaused = true
        isPlaying = false
    }

    func togglePlay() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func cancelLoads() {
        stop()
    }

    func stop() {
        #if !os(macOS)
            model.setAudioSessionActive(false)
        #endif
        stopClientUpdates()
        stopRefreshRateUpdates()
        client?.stop()
        isPlaying = false
        isPaused = false
        hasStarted = false
    }

    func seek(to time: CMTime, seekType _: SeekType, completionHandler: ((Bool) -> Void)?) {
        client?.seek(to: time) { [weak self] _ in
            self?.getTimeUpdates()
            self?.updateControls()
            completionHandler?(true)
        }
    }

    func setRate(_ rate: Double) {
        client?.setDoubleAsync("speed", rate)
    }

    func closeItem() {
        pause()
        stop()
        self.video = nil
        self.stream = nil
    }

    func closePiP() {}

    func startControlsUpdates() {
        guard model.presentingPlayer, model.controls.presentingControls, !model.controls.presentingOverlays else {
            self.logger.info("ignored controls update start")
            return
        }
        self.logger.info("starting controls updates")
        controlsUpdates = true
    }

    func stopControlsUpdates() {
        self.logger.info("stopping controls updates")
        controlsUpdates = false
    }

    func startClientUpdates() {
        clientTimer.start()
    }

    private var handleSegmentsThrottle = Throttle(interval: 1)

    func getTimeUpdates() {
        currentTime = client?.currentTime
        playerItemDuration = client?.duration

        if controlsUpdates {
            updateControls()
        }

        model.updateNowPlayingInfo()

        handleSegmentsThrottle.execute {
            if let currentTime {
                model.handleSegments(at: currentTime)
            }
        }

        timeObserverThrottle.execute {
            self.model.updateWatch(time: self.currentTime)
        }

        self.model.updateTime(self.currentTime!)
    }

    private func stopClientUpdates() {
        clientTimer.pause()
    }

    private func updateControlsIsPlaying() {
        guard model.activeBackend == .mpv else { return }
        DispatchQueue.main.async { [weak self] in
            self?.controls.isPlaying = self?.isPlaying ?? false
        }
    }

    private func checkAndUpdateRefreshRate() {
        guard let screenRefreshRate = client?.getScreenRefreshRate() else {
            logger.warning("Failed to get screen refresh rate.")
            return
        }

        let contentFps = client?.currentContainerFps ?? screenRefreshRate

        guard Defaults[.mpvSetRefreshToContentFPS] else {
            // If the current refresh rate doesn't match the screen refresh rate, reset it
            if client?.currentRefreshRate != screenRefreshRate {
                client?.updateRefreshRate(to: screenRefreshRate)
                client?.currentRefreshRate = screenRefreshRate
                #if !os(macOS)
                    notifyViewToUpdateDisplayLink(with: screenRefreshRate)
                #endif
                logger.info("Reset refresh rate to screen's rate: \(screenRefreshRate) Hz")
            }
            return
        }

        // Adjust the refresh rate to match the content if it differs
        if screenRefreshRate != contentFps {
            client?.updateRefreshRate(to: contentFps)
            client?.currentRefreshRate = contentFps
            #if !os(macOS)
                notifyViewToUpdateDisplayLink(with: contentFps)
            #endif
            logger.info("Adjusted screen refresh rate to match content: \(contentFps) Hz")
        } else if client?.currentRefreshRate != screenRefreshRate {
            // Ensure the refresh rate is set back to the screen's rate if no adjustment is needed
            client?.updateRefreshRate(to: screenRefreshRate)
            client?.currentRefreshRate = screenRefreshRate
            #if !os(macOS)
                notifyViewToUpdateDisplayLink(with: screenRefreshRate)
            #endif
            logger.info("Checked and reset refresh rate to screen's rate: \(screenRefreshRate) Hz")
        }
    }

    #if !os(macOS)
        private func notifyViewToUpdateDisplayLink(with refreshRate: Int) {
            NotificationCenter.default.post(name: .updateDisplayLinkFrameRate, object: nil, userInfo: ["refreshRate": refreshRate])
        }
    #endif

    func handle(_ event: UnsafePointer<mpv_event>!) {
        logger.info(.init(stringLiteral: "RECEIVED  event: \(String(cString: mpv_event_name(event.pointee.event_id)))"))

        switch event.pointee.event_id {
        case MPV_EVENT_SHUTDOWN:
            mpv_destroy(client.mpv)
            client.mpv = nil

        case MPV_EVENT_LOG_MESSAGE:
            let logmsg = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(event.pointee.data))
            logger.info(.init(stringLiteral: "\(String(cString: (logmsg!.pointee.prefix)!)), "
                    + "\(String(cString: (logmsg!.pointee.level)!)), "
                    + "\(String(cString: (logmsg!.pointee.text)!))"))

        case MPV_EVENT_FILE_LOADED:
            onFileLoaded?()
            startClientUpdates()
            onFileLoaded = nil

        case MPV_EVENT_PROPERTY_CHANGE:
            let dataOpaquePtr = OpaquePointer(event.pointee.data)
            if let property = UnsafePointer<mpv_event_property>(dataOpaquePtr)?.pointee {
                let propertyName = String(cString: property.name)
                handlePropertyChange(propertyName, property)
            }

        case MPV_EVENT_PLAYBACK_RESTART:
            isLoadingVideo = false
            isSeeking = false

            onFileLoaded?()
            startClientUpdates()
            onFileLoaded = nil

        case MPV_EVENT_VIDEO_RECONFIG:
            model.updateAspectRatio()

        case MPV_EVENT_SEEK:
            isSeeking = true

        case MPV_EVENT_END_FILE:
            let reason = event!.pointee.data.load(as: mpv_end_file_reason.self)

            if reason != MPV_END_FILE_REASON_STOP {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    NavigationModel.shared.presentAlert(title: "Error while opening file")
                    self.model.closeCurrentItem(finished: true)
                    self.getTimeUpdates()
                    self.eofPlaybackModeAction()
                }
            } else {
                DispatchQueue.main.async { [weak self] in self?.handleEndOfFile() }
            }

        default:
            logger.info(.init(stringLiteral: "UNHANDLED event: \(String(cString: mpv_event_name(event.pointee.event_id)))"))
        }
    }

    func handleEndOfFile() {
        guard client.eofReached else {
            return
        }
        eofPlaybackModeAction()
    }

    func setNeedsDrawing(_ needsDrawing: Bool) {
        client?.setNeedsDrawing(needsDrawing)
    }

    func setSize(_ width: Double, _ height: Double) {
        client?.setSize(width, height)
    }

    func addVideoTrack(_ url: URL) {
        client?.addVideoTrack(url)
    }

    func addSubTrack(_ url: URL) {
        Task {
            if let areSubtitlesAdded = client?.areSubtitlesAdded {
                if await areSubtitlesAdded() {
                    await client?.removeSubs()
                }
            }
            await client?.addSubTrack(url)
        }
    }

    func setVideoToAuto() {
        client?.setVideoToAuto()
    }

    func setVideoToNo() {
        client?.setVideoToNo()
    }

    func updateNetworkState() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let client = self.client else { return }
            self.networkState.pausedForCache = client.pausedForCache
            self.networkState.cacheDuration = client.cacheDuration
            self.networkState.bufferingState = client.bufferingState
        }

        if !networkState.needsUpdates {
            networkStateTimer.pause()
        }
    }

    func setNeedsNetworkStateUpdates(_ needsUpdates: Bool) {
        if needsUpdates {
            networkStateTimer.start()
        } else {
            networkStateTimer.pause()
        }
    }

    func startMusicMode() {
        setVideoToNo()
    }

    func stopMusicMode() {
        addVideoTrackFromStream()
        setVideoToAuto()

        controls.resetTimer()
    }

    func addVideoTrackFromStream() {
        if let videoTrackURL = model.stream?.videoAsset?.url,
           tracks < 2
        {
            logger.info("adding video track")
            addVideoTrack(videoTrackURL)
        }

        setVideoToAuto()
    }

    func didChangeTo() {
        setNeedsDrawing(model.presentingPlayer)

        if model.musicMode {
            startMusicMode()
        } else {
            stopMusicMode()
        }
    }

    private func handleCaptionsChange() async {
        guard let captions else {
            if let isSubtitlesAdded = client?.areSubtitlesAdded, await isSubtitlesAdded() {
                await client?.removeSubs()
            }
            return
        }

        addSubTrack(captions.url)
    }

    private func handlePropertyChange(_ name: String, _ property: mpv_event_property) {
        switch name {
        case "pause":
            if let paused = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
                if paused {
                    DispatchQueue.main.async { [weak self] in self?.handleEndOfFile() }
                } else {
                    isLoadingVideo = false
                    isSeeking = false
                }
                isPlaying = !paused
                networkStateTimer.start()
            }
        case "core-idle":
            if let idle = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
                if !idle {
                    isLoadingVideo = false
                    isSeeking = false
                    networkStateTimer.start()
                }
            }
        default:
            logger.info("MPV backend received unhandled property: \(name)")
        }
    }
}
