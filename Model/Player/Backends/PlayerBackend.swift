import CoreMedia
import Defaults
import Foundation
#if !os(macOS)
    import UIKit
#endif

protocol PlayerBackend {
    var model: PlayerModel! { get set }
    var controls: PlayerControlsModel! { get set }
    var playerTime: PlayerTimeModel! { get set }
    var seek: SeekModel! { get set }
    var networkState: NetworkStateModel! { get set }

    var stream: Stream? { get set }
    var video: Video? { get set }
    var currentTime: CMTime? { get }

    var loadedVideo: Bool { get }
    var isLoadingVideo: Bool { get }

    var isPlaying: Bool { get }
    var isSeeking: Bool { get }
    var playerItemDuration: CMTime? { get }

    var aspectRatio: Double { get }
    var controlsUpdates: Bool { get }

    func bestPlayable(_ streams: [Stream], maxResolution: ResolutionSetting) -> Stream?
    func canPlay(_ stream: Stream) -> Bool

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

    func setRate(_ rate: Float)

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
}

extension PlayerBackend {
    func seek(to time: CMTime, seekType: SeekType, completionHandler: ((Bool) -> Void)? = nil) {
        seek.registerSeek(at: time, type: seekType, restore: currentTime)
        seek(to: time, seekType: seekType, completionHandler: completionHandler)
    }

    func seek(to seconds: Double, seekType: SeekType, completionHandler: ((Bool) -> Void)? = nil) {
        let seconds = CMTime.secondsInDefaultTimescale(seconds)
        seek.registerSeek(at: seconds, type: seekType, restore: currentTime)
        seek(to: seconds, seekType: seekType, completionHandler: completionHandler)
    }

    func seek(relative time: CMTime, seekType: SeekType, completionHandler: ((Bool) -> Void)? = nil) {
        if let currentTime = currentTime, let duration = playerItemDuration {
            let seekTime = min(max(0, currentTime.seconds + time.seconds), duration.seconds)
            seek.registerSeek(at: .secondsInDefaultTimescale(seekTime), type: seekType, restore: currentTime)
            seek(to: seekTime, seekType: seekType, completionHandler: completionHandler)
        }
    }

    func eofPlaybackModeAction() {
        switch model.playbackMode {
        case .queue, .shuffle:
            if Defaults[.closeLastItemOnPlaybackEnd] {
                model.prepareCurrentItemForHistory(finished: true)
            }

            if model.queue.isEmpty {
                if Defaults[.closeLastItemOnPlaybackEnd] {
                    model.resetQueue()
                    model.hide()
                }
            } else {
                model.advanceToNextItem()
            }
        case .loopOne:
            model.backend.seek(to: .zero, seekType: .loopRestart) { _ in
                self.model.play()
            }
        case .related:
            guard let item = model.autoplayItem else { return }
            model.resetAutoplay()
            model.advanceToItem(item)
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
            self.playerTime.currentTime = self.currentTime ?? .zero
            self.playerTime.duration = self.playerItemDuration ?? .zero
            completionHandler?()
        }
    }
}
