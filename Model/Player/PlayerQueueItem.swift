import AVFoundation
import Defaults
import Foundation

struct PlayerQueueItem: Hashable, Identifiable, Defaults.Serializable {
    static let bridge = PlayerQueueItemBridge()

    var id = UUID()
    var video: Video!
    var videoID: Video.ID
    var app: VideosApp?
    var instanceURL: URL?
    var playbackTime: CMTime?
    var videoDuration: TimeInterval?

    static func from(_ watch: Watch, video: Video? = nil) -> Self {
        .init(
            video,
            videoID: watch.videoID,
            app: watch.app,
            instanceURL: watch.instanceURL,
            playbackTime: CMTime.secondsInDefaultTimescale(watch.stoppedAt),
            videoDuration: watch.videoDuration
        )
    }

    init(
        _ video: Video? = .fixture,
        videoID: Video.ID? = nil,
        app: VideosApp? = nil,
        instanceURL: URL? = nil,
        playbackTime: CMTime? = nil,
        videoDuration: TimeInterval? = nil
    ) {
        self.video = video
        self.videoID = videoID ?? video!.videoID
        self.app = app
        self.instanceURL = instanceURL
        self.playbackTime = playbackTime
        self.videoDuration = videoDuration
    }

    var duration: TimeInterval {
        videoDuration ?? video?.length ?? .zero
    }

    var shouldRestartPlaying: Bool {
        guard Defaults[.watchedVideoPlayNowBehavior] == .continue else { return true }

        guard let seconds = playbackTime?.seconds else {
            return false
        }

        if duration <= 0 {
            return false
        }

        return (seconds / duration) * 100 > Double(Defaults[.watchedThreshold])
    }

    var hasDetailsLoaded: Bool {
        guard let video else { return false }
        return !video.streams.isEmpty
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
