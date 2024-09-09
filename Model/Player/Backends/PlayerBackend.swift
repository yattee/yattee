import CoreMedia
import Defaults
import Foundation
import Logging
#if !os(macOS)
    import UIKit
#endif

protocol PlayerBackend {
    var suggestedPlaybackRates: [Double] { get }
    var model: PlayerModel { get }
    var controls: PlayerControlsModel { get }
    var playerTime: PlayerTimeModel { get }
    var networkState: NetworkStateModel { get }

    var stream: Stream? { get set }
    var video: Video? { get set }
    var currentTime: CMTime? { get }

    var loadedVideo: Bool { get }
    var isLoadingVideo: Bool { get }

    var hasStarted: Bool { get }
    var isPaused: Bool { get }
    var isPlaying: Bool { get }
    var isSeeking: Bool { get }
    var playerItemDuration: CMTime? { get }

    var aspectRatio: Double { get }
    var controlsUpdates: Bool { get }

    var videoWidth: Double? { get }
    var videoHeight: Double? { get }

    func canPlay(_ stream: Stream) -> Bool
    func canPlayAtRate(_ rate: Double) -> Bool

    func playStream(
        _ stream: Stream,
        of video: Video,
        preservingTime: Bool,
        upgrading: Bool
    )

    func play()
    func pause()
    func togglePlay()

    func stop()

    func seek(to time: CMTime, seekType: SeekType, completionHandler: ((Bool) -> Void)?)
    func seek(to seconds: Double, seekType: SeekType, completionHandler: ((Bool) -> Void)?)

    func setRate(_ rate: Double)

    func closeItem()

    func closePiP()

    func startMusicMode()
    func stopMusicMode()

    func getTimeUpdates()
    func updateControls(completionHandler: (() -> Void)?)
    func startControlsUpdates()
    func stopControlsUpdates()

    func didChangeTo()

    func setNeedsNetworkStateUpdates(_ needsUpdates: Bool)

    func setNeedsDrawing(_ needsDrawing: Bool)
    func setSize(_ width: Double, _ height: Double)

    func cancelLoads()
}

extension PlayerBackend {
    var logger: Logger {
        return Logger(label: "stream.yattee.player.backend")
    }

    func seek(to time: CMTime, seekType: SeekType, completionHandler: ((Bool) -> Void)? = nil) {
        model.seek.registerSeek(at: time, type: seekType, restore: currentTime)
        seek(to: time, seekType: seekType, completionHandler: completionHandler)
    }

    func seek(to seconds: Double, seekType: SeekType, completionHandler: ((Bool) -> Void)? = nil) {
        let seconds = CMTime.secondsInDefaultTimescale(seconds)
        model.seek.registerSeek(at: seconds, type: seekType, restore: currentTime)
        seek(to: seconds, seekType: seekType, completionHandler: completionHandler)
    }

    func seek(relative time: CMTime, seekType: SeekType, completionHandler: ((Bool) -> Void)? = nil) {
        if let currentTime, let duration = playerItemDuration {
            let seekTime = min(max(0, currentTime.seconds + time.seconds), duration.seconds)
            model.seek.registerSeek(at: .secondsInDefaultTimescale(seekTime), type: seekType, restore: currentTime)
            seek(to: seekTime, seekType: seekType, completionHandler: completionHandler)
        }
    }

    func eofPlaybackModeAction() {
        let loopAction = {
            model.backend.seek(to: .zero, seekType: .loopRestart) { _ in
                self.model.play()
            }
        }

        guard model.playbackMode != .loopOne else {
            loopAction()
            return
        }

        switch model.playbackMode {
        case .queue, .shuffle:
            model.prepareCurrentItemForHistory(finished: true)

            if model.queue.isEmpty {
                #if os(tvOS)
                    if Defaults[.closeVideoOnEOF] {
                        if model.activeBackend == .appleAVPlayer {
                            model.avPlayerBackend.controller?.dismiss(animated: false)
                        }
                        model.resetQueue()
                        model.hide()
                    }
                #else
                    if Defaults[.closeVideoOnEOF] {
                        model.resetQueue()
                        model.hide()
                    } else if Defaults[.exitFullscreenOnEOF], model.playingFullScreen {
                        model.exitFullScreen()
                    }
                #endif
            } else {
                model.advanceToNextItem()
            }
        case .loopOne:
            loopAction()
        case .related:
            guard let item = model.autoplayItem else { return }
            model.resetAutoplay()
            model.advanceToItem(item)
        }
    }

    func bestPlayable(_ streams: [Stream], maxResolution: ResolutionSetting, formatOrder: [QualityProfile.Format]) -> Stream? {
        logger.info("Starting bestPlayable function")
        logger.info("Total streams received: \(streams.count)")
        logger.info("Max resolution allowed: \(String(describing: maxResolution.value))")
        logger.info("Format order: \(formatOrder)")

        // Filter out non-HLS streams and streams with resolution more than maxResolution
        let nonHLSStreams = streams.filter {
            let isHLS = $0.kind == .hls
            // Check if the stream's resolution is within the maximum allowed resolution
            let isWithinResolution = $0.resolution.map { $0 <= maxResolution.value } ?? false

            logger.info("Stream ID: \($0.id) - Kind: \(String(describing: $0.kind)) - Resolution: \(String(describing: $0.resolution)) - Bitrate: \($0.bitrate ?? 0)")
            logger.info("Is HLS: \(isHLS), Is within resolution: \(isWithinResolution)")
            return !isHLS && isWithinResolution
        }
        logger.info("Non-HLS streams after filtering: \(nonHLSStreams.count)")

        // Find max resolution and bitrate from non-HLS streams
        let bestResolutionStream = nonHLSStreams.max { $0.resolution < $1.resolution }
        let bestBitrateStream = nonHLSStreams.max { $0.bitrate ?? 0 < $1.bitrate ?? 0 }

        logger.info("Best resolution stream: \(String(describing: bestResolutionStream?.id)) with resolution: \(String(describing: bestResolutionStream?.resolution))")
        logger.info("Best bitrate stream: \(String(describing: bestBitrateStream?.id)) with bitrate: \(String(describing: bestBitrateStream?.bitrate))")

        let bestResolution = bestResolutionStream?.resolution ?? maxResolution.value
        let bestBitrate = bestBitrateStream?.bitrate ?? bestResolutionStream?.resolution.bitrate ?? maxResolution.value.bitrate

        logger.info("Final best resolution selected: \(String(describing: bestResolution))")
        logger.info("Final best bitrate selected: \(bestBitrate)")

        let adjustedStreams = streams.map { stream in
            if stream.kind == .hls {
                logger.info("Adjusting HLS stream ID: \(stream.id)")
                stream.resolution = bestResolution
                stream.bitrate = bestBitrate
                stream.format = .hls
            } else if stream.kind == .stream {
                logger.info("Adjusting non-HLS stream ID: \(stream.id)")
                stream.format = .stream
            }
            return stream
        }

        let filteredStreams = adjustedStreams.filter { stream in
            // Check if the stream's resolution is within the maximum allowed resolution
            let isWithinResolution = stream.resolution <= maxResolution.value
            logger.info("Filtered stream ID: \(stream.id) - Is within max resolution: \(isWithinResolution)")
            return isWithinResolution
        }

        logger.info("Filtered streams count after adjustments: \(filteredStreams.count)")

        let bestStream = filteredStreams.max { lhs, rhs in
            if lhs.resolution == rhs.resolution {
                guard let lhsFormat = QualityProfile.Format(rawValue: lhs.format.rawValue),
                      let rhsFormat = QualityProfile.Format(rawValue: rhs.format.rawValue)
                else {
                    logger.info("Failed to extract lhsFormat or rhsFormat for streams \(lhs.id) and \(rhs.id)")
                    return false
                }

                let lhsFormatIndex = formatOrder.firstIndex(of: lhsFormat) ?? Int.max
                let rhsFormatIndex = formatOrder.firstIndex(of: rhsFormat) ?? Int.max

                logger.info("Comparing formats for streams \(lhs.id) and \(rhs.id) - LHS Format Index: \(lhsFormatIndex), RHS Format Index: \(rhsFormatIndex)")

                return lhsFormatIndex > rhsFormatIndex
            }

            logger.info("Comparing resolutions for streams \(lhs.id) and \(rhs.id) - LHS Resolution: \(String(describing: lhs.resolution)), RHS Resolution: \(String(describing: rhs.resolution))")

            return lhs.resolution < rhs.resolution
        }

        logger.info("Best stream selected: \(String(describing: bestStream?.id)) with resolution: \(String(describing: bestStream?.resolution)) and format: \(String(describing: bestStream?.format))")

        return bestStream
    }

    func updateControls(completionHandler: (() -> Void)? = nil) {
        logger.info("updating controls")

        guard model.presentingPlayer, !model.controls.presentingOverlays else {
            logger.info("ignored controls update")
            completionHandler?()
            return
        }

        DispatchQueue.main.async(qos: .userInteractive) {
            #if !os(macOS)
                guard UIApplication.shared.applicationState != .background else {
                    logger.info("not performing controls updates in background")
                    completionHandler?()
                    return
                }
            #endif
            PlayerTimeModel.shared.currentTime = self.currentTime ?? .zero
            PlayerTimeModel.shared.duration = self.playerItemDuration ?? .zero
            completionHandler?()
        }
    }
}
