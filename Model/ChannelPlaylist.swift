import Foundation
import SwiftyJSON

struct ChannelPlaylist: Identifiable {
    var id: String
    var title: String
    var thumbnailURL: URL?
    var channel: Channel?
    var videos = [Video]()
    var videosCount: Int?

    var cacheKey: String {
        "channelplaylists-\(id)"
    }

    var json: JSON {
        [
            "id": id,
            "title": title,
            "thumbnailURL": thumbnailURL?.absoluteString ?? "",
            "channel": channel?.json.object ?? "",
            "videos": videos.map(\.json.object),
            "videosCount": String(videosCount ?? 0)
        ]
    }

    static func from(_ json: JSON) -> Self {
        Self(
            id: json["id"].stringValue,
            title: json["title"].stringValue,
            thumbnailURL: json["thumbnailURL"].url,
            channel: Channel.from(json["channel"]),
            videos: json["videos"].arrayValue.map { Video.from($0) },
            videosCount: json["videosCount"].int
        )
    }
}
