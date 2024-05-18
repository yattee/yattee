import CoreMedia
import Defaults
import Foundation
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
                if Defaults[.closeVideoOnEOF] {
                    #if os(tvOS)
                        if model.activeBackend == .appleAVPlayer {
                            model.avPlayerBackend.controller?.dismiss(animated: false)
                        }
                    #endif
                    model.resetQueue()
                    model.hide()
                }
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
        // filter out non HLS streams
        let nonHLSStreams = streams.filter { $0.kind != .hls }

        // find max resolution from non HLS streams
        let bestResolution = nonHLSStreams
            .filter { $0.resolution <= maxResolution.value }
            .max { $0.resolution < $1.resolution }

        // finde max bitrate from non HLS streams
        let bestBitrate = nonHLSStreams
            .filter { $0.resolution <= maxResolution.value }
            .max { $0.bitrate ?? 0 < $1.bitrate ?? 0 }

        return streams.map { stream in
            if stream.kind == .hls {
                stream.resolution = bestResolution?.resolution ?? maxResolution.value
                stream.bitrate = bestBitrate?.bitrate ?? (bestResolution?.resolution.bitrate ?? maxResolution.value.bitrate)
                stream.format = .hls
            } else if stream.kind == .stream {
                stream.format = .stream
            }
            return stream
        }
        .filter { stream in
            stream.resolution <= maxResolution.value
        }
        .max { lhs, rhs in
            if lhs.resolution == rhs.resolution {
                guard let lhsFormat = QualityProfile.Format(rawValue: lhs.format.rawValue),
                      let rhsFormat = QualityProfile.Format(rawValue: rhs.format.rawValue)
                else {
                    print("Failed to extract lhsFormat or rhsFormat")
                    return false
                }

                let lhsFormatIndex = formatOrder.firstIndex(of: lhsFormat) ?? Int.max
                let rhsFormatIndex = formatOrder.firstIndex(of: rhsFormat) ?? Int.max

                return lhsFormatIndex > rhsFormatIndex
            }

            return lhs.resolution < rhs.resolution
        }
    }

    func updateControls(completionHandler: (() -> Void)? = nil) {
        print("updating controls")

        guard model.presentingPlayer, !model.controls.presentingOverlays else {
            print("ignored controls update")
            completionHandler?()
            return
        }

        DispatchQueue.main.async(qos: .userInteractive) {
            #if !os(macOS)
                guard UIApplication.shared.applicationState != .background else {
                    print("not performing controls updates in background")
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
