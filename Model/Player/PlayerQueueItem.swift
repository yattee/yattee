import AVFoundation
import Foundation

struct PlayerQueueItem: Hashable, Identifiable {
    var id = UUID()
    var video: Video
    var playbackTime: CMTime?
    var videoDuration: TimeInterval?

    init(_ video: Video, playbackTime: CMTime? = nil, videoDuration: TimeInterval? = nil) {
        self.video = video
        self.playbackTime = playbackTime
        self.videoDuration = videoDuration
    }

    var duration: TimeInterval {
        videoDuration ?? video.length
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
