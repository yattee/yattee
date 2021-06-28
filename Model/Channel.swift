import AVFoundation
import Defaults
import Foundation

struct Channel: Codable, Defaults.Serializable {
    var id: String
    var name: String

    static func from(video: Video) -> Channel {
        Channel(id: video.channelID, name: video.author)
    }
}
