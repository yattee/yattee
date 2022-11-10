import CoreMedia
import Defaults
import Foundation

struct PlayerQueueItemBridge: Defaults.Bridge {
    typealias Value = PlayerQueueItem
    typealias Serializable = [String: String]

    func serialize(_ value: Value?) -> Serializable? {
        guard let value else {
            return nil
        }

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

        var localURL = ""
        if let video = value.video, video.isLocal {
            localURL = video.localStream?.localURL.absoluteString ?? ""
        }

        return [
            "localURL": localURL,
            "videoID": value.videoID,
            "playbackTime": playbackTime,
            "videoDuration": videoDuration
        ]
    }

    func deserialize(_ object: Serializable?) -> Value? {
        guard let object else { return nil }

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

        if let localUrlString = object["localURL"],
           !localUrlString.isEmpty,
           let localURL = URL(string: localUrlString)
        {
            return PlayerQueueItem(
                .local(localURL),
                playbackTime: playbackTime,
                videoDuration: videoDuration
            )
        }

        guard let videoID = object["videoID"] else { return nil }

        return PlayerQueueItem(
            videoID: videoID,
            playbackTime: playbackTime,
            videoDuration: videoDuration
        )
    }
}
