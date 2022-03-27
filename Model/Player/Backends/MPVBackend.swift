import AVFAudio
import CoreMedia
import Foundation
import Logging
import SwiftUI

final class MPVBackend: PlayerBackend {
    private var logger = Logger(label: "mpv-backend")

    var model: PlayerModel!
    var controls: PlayerControlsModel!

    var stream: Stream?
    var video: Video?
    var currentTime: CMTime?

    var loadedVideo = false
    var isLoadingVideo = true { didSet {
        DispatchQueue.main.async { [weak self] in
            self?.controls.isLoadingVideo = self?.isLoadingVideo ?? true
        }
    }}

    var isPlaying = true { didSet {
        if isPlaying {
            startClientUpdates()
        } else {
            stopControlsUpdates()
        }

        updateControlsIsPlaying()
    }}
    var playerItemDuration: CMTime?

    #if !os(macOS)
        var controller: MPVViewController!
    #endif
    var client: MPVClient! { didSet { client.backend = self } }

    private var clientTimer: RepeatingTimer!

    private var onFileLoaded: (() -> Void)?

    private var controlsUpdates = false
    private var timeObserverThrottle = Throttle(interval: 2)

    init(model: PlayerModel, controls: PlayerControlsModel? = nil) {
        self.model = model
        self.controls = controls

        clientTimer = .init(timeInterval: 1)
        clientTimer.eventHandler = getClientUpdates
    }

    func bestPlayable(_ streams: [Stream], maxResolution: ResolutionSetting) -> Stream? {
        streams
            .filter { $0.kind == .adaptive && $0.resolution <= maxResolution.value }
            .max { $0.resolution < $1.resolution } ??
            streams.first { $0.kind == .hls } ??
            streams.first
    }

    func canPlay(_ stream: Stream) -> Bool {
        stream.resolution != .unknown && stream.format != "AV1"
    }

    func playStream(_ stream: Stream, of video: Video, preservingTime: Bool, upgrading _: Bool) {
        let updateCurrentStream = {
            DispatchQueue.main.async { [weak self] in
                self?.stream = stream
                self?.video = video
                self?.model.stream = stream
            }
        }

        let startPlaying = {
            #if !os(macOS)
                try? AVAudioSession.sharedInstance().setActive(true)
            #endif

            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    return
                }

                self.startClientUpdates()

                if !preservingTime,
                   let segment = self.model.sponsorBlock.segments.first,
                   segment.start < 3,
                   self.model.lastSkipped.isNil
                {
                    self.seek(to: segment.endTime) { finished in
                        guard finished else {
                            return
                        }

                        self.model.lastSkipped = segment
                        self.play()
                    }
                } else {
                    self.play()
                }
            }
        }

        let replaceItem: (CMTime?) -> Void = { [weak self] time in
            guard let self = self else {
                return
            }

            self.stop()

            if let url = stream.singleAssetURL {
                self.onFileLoaded = {
                    updateCurrentStream()
                    startPlaying()
                }

                self.client.loadFile(url, time: time) { [weak self] _ in
                    self?.isLoadingVideo = true
                }
            } else {
                self.onFileLoaded = { [weak self] in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self?.client.addAudio(stream.audioAsset.url) { _ in
                            updateCurrentStream()
                            startPlaying()
                        }
                    }
                }

                self.client.loadFile(stream.videoAsset.url, time: time) { [weak self] _ in
                    self?.isLoadingVideo = true
                    self?.pause()
                }
            }
        }

        if preservingTime {
            if model.preservedTime.isNil {
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

    func play() {
        isPlaying = true
        startClientUpdates()

        if controls.presentingControls {
            startControlsUpdates()
        }

        client?.play()
    }

    func pause() {
        isPlaying = false
        stopClientUpdates()

        client?.pause()
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func stop() {
        client?.stop()
    }

    func seek(to time: CMTime, completionHandler: ((Bool) -> Void)?) {
        client.seek(to: time) { [weak self] _ in
            self?.getClientUpdates()
            self?.updateControls()
            completionHandler?(true)
        }
    }

    func seek(relative time: CMTime, completionHandler: ((Bool) -> Void)? = nil) {
        client.seek(relative: time) { [weak self] _ in
            self?.getClientUpdates()
            self?.updateControls()
            completionHandler?(true)
        }
    }

    func setRate(_: Float) {
        // TODO: Implement rate change
    }

    func closeItem() {}

    func enterFullScreen() {}

    func exitFullScreen() {}

    func closePiP(wasPlaying _: Bool) {}

    func updateControls() {
        DispatchQueue.main.async { [weak self] in
            self?.logger.info("updating controls")
            self?.controls.currentTime = self?.currentTime ?? .zero
            self?.controls.duration = self?.playerItemDuration ?? .zero
        }
    }

    func startControlsUpdates() {
        self.logger.info("starting controls updates")
        controlsUpdates = true
    }

    func stopControlsUpdates() {
        self.logger.info("stopping controls updates")
        controlsUpdates = false
    }

    func startClientUpdates() {
        clientTimer.resume()
    }

    private func getClientUpdates() {
        self.logger.info("getting client updates")

        currentTime = client?.currentTime
        playerItemDuration = client?.duration

        if controlsUpdates {
            updateControls()
        }

        model.updateNowPlayingInfo()

        if let currentTime = currentTime {
            model.handleSegments(at: currentTime)
        }

        timeObserverThrottle.execute {
            self.model.updateWatch()
        }
    }

    private func stopClientUpdates() {
        clientTimer.suspend()
    }

    private func updateControlsIsPlaying() {
        DispatchQueue.main.async { [weak self] in
            self?.controls.isPlaying = self?.isPlaying ?? false
        }
    }

    func handle(_ event: UnsafePointer<mpv_event>!) {
        logger.info("\(String(cString: mpv_event_name(event.pointee.event_id)))")

        switch event.pointee.event_id {
        case MPV_EVENT_SHUTDOWN:
            mpv_destroy(client.mpv)
            client.mpv = nil

        case MPV_EVENT_LOG_MESSAGE:
            let logmsg = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(event.pointee.data))
            logger.info(.init(stringLiteral: "log: \(String(cString: (logmsg!.pointee.prefix)!)), "
                    + "\(String(cString: (logmsg!.pointee.level)!)), "
                    + "\(String(cString: (logmsg!.pointee.text)!))"))

        case MPV_EVENT_FILE_LOADED:
            onFileLoaded?()
            startClientUpdates()
            onFileLoaded = nil

        case MPV_EVENT_PLAYBACK_RESTART:
            isLoadingVideo = false

            onFileLoaded?()
            startClientUpdates()
            onFileLoaded = nil

        case MPV_EVENT_UNPAUSE:
            isLoadingVideo = false

        case MPV_EVENT_END_FILE:
            DispatchQueue.main.async { [weak self] in
                self?.handleEndOfFile(event)
            }

        default:
            logger.info(.init(stringLiteral: "event: \(String(cString: mpv_event_name(event.pointee.event_id)))"))
        }
    }

    func handleEndOfFile(_: UnsafePointer<mpv_event>!) {
        guard !isLoadingVideo else {
            return
        }

        model.prepareCurrentItemForHistory(finished: true)

        if model.queue.isEmpty {
            #if !os(macOS)
                try? AVAudioSession.sharedInstance().setActive(false)
            #endif
            model.resetQueue()

            model.hide()
        } else {
            model.advanceToNextItem()
        }
    }

    func setNeedsDrawing(_ needsDrawing: Bool) {
        client?.setNeedsDrawing(needsDrawing)
    }

    func setSize(_ width: Double, _ height: Double) {
        self.client?.setSize(width, height)
    }
}
