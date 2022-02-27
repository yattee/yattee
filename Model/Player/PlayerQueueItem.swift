import AVFoundation
import Defaults
import Foundation

struct PlayerQueueItem: Hashable, Identifiable, Defaults.Serializable {
    static let bridge = PlayerQueueItemBridge()

    var id = UUID()
    var video: Video!
    var videoID: Video.ID
    var playbackTime: CMTime?
    var videoDuration: TimeInterval?

    static func from(_ watch: Watch, video: Video? = nil) -> Self {
        .init(
            video,
            videoID: watch.videoID,
            playbackTime: CMTime.secondsInDefaultTimescale(watch.stoppedAt),
            videoDuration: watch.videoDuration
        )
    }

    init(_ video: Video? = nil, videoID: Video.ID? = nil, playbackTime: CMTime? = nil, videoDuration: TimeInterval? = nil) {
        self.video = video
        self.videoID = videoID ?? video!.videoID
        self.playbackTime = playbackTime
        self.videoDuration = videoDuration
    }

    var duration: TimeInterval {
        videoDuration ?? video?.length ?? .zero
    }

    var shouldRestartPlaying: Bool {
        guard let seconds = playbackTime?.seconds else {
            return false
        }

        return duration - seconds <= 10
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
