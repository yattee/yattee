import CoreMedia
import Defaults
import Foundation

protocol PlayerBackend {
    var model: PlayerModel! { get set }
    var controls: PlayerControlsModel! { get set }
    var playerTime: PlayerTimeModel! { get set }
    var networkState: NetworkStateModel! { get set }

    var stream: Stream? { get set }
    var video: Video? { get set }
    var currentTime: CMTime? { get }

    var loadedVideo: Bool { get }
    var isLoadingVideo: Bool { get }

    var isPlaying: Bool { get }
    var isSeeking: Bool { get }
    var playerItemDuration: CMTime? { get }

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

    func seek(to time: CMTime, completionHandler: ((Bool) -> Void)?)
    func seek(to seconds: Double, completionHandler: ((Bool) -> Void)?)
    func seek(relative time: CMTime, completionHandler: ((Bool) -> Void)?)

    func setRate(_ rate: Float)

    func closeItem()

    func enterFullScreen()
    func exitFullScreen()

    func closePiP(wasPlaying: Bool)

    func updateControls()
    func startControlsUpdates()
    func stopControlsUpdates()

    func setNeedsNetworkStateUpdates()

    func setNeedsDrawing(_ needsDrawing: Bool)
    func setSize(_ width: Double, _ height: Double)
}

extension PlayerBackend {
    func seek(to time: CMTime, completionHandler: ((Bool) -> Void)? = nil) {
        seek(to: time, completionHandler: completionHandler)
    }

    func seek(to seconds: Double, completionHandler: ((Bool) -> Void)? = nil) {
        seek(to: .secondsInDefaultTimescale(seconds), completionHandler: completionHandler)
    }

    func seek(relative time: CMTime, completionHandler: ((Bool) -> Void)? = nil) {
        seek(relative: time, completionHandler: completionHandler)
    }
}
