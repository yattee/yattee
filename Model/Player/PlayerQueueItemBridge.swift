import CoreMedia
import Defaults
import Foundation

struct PlayerQueueItemBridge: Defaults.Bridge {
    typealias Value = PlayerQueueItem
    typealias Serializable = [String: String]

    func serialize(_ value: Value?) -> Serializable? {
        guard let value = value else {
            return nil
        }

        let videoID = value.videoID.isEmpty ? value.video!.videoID : value.videoID

        var playbackTime = ""
        if let time = value.playbackTime {
            if time.seconds.isFinite {
                playbackTime = String(time.seconds)
            }
        }

        var videoDuration = ""
        if let duration = value.videoDuration {
            if duration.isFinite {
                videoDuration = String(duration)
            }
        }

        return [
            "videoID": videoID,
            "playbackTime": playbackTime,
            "videoDuration": videoDuration
        ]
    }

    func deserialize(_ object: Serializable?) -> Value? {
        guard
            let object = object,
            let videoID = object["videoID"]
        else {
            return nil
        }

        var playbackTime: CMTime?
        var videoDuration: TimeInterval?

        if let time = object["playbackTime"],
           !time.isEmpty,
           let seconds = TimeInterval(time)
        {
            playbackTime = .secondsInDefaultTimescale(seconds)
        }

        if let duration = object["videoDuration"],
           !duration.isEmpty
        {
            videoDuration = TimeInterval(duration)
        }

        return PlayerQueueItem(
            videoID: videoID,
            playbackTime: playbackTime,
            videoDuration: videoDuration
        )
    }
}
