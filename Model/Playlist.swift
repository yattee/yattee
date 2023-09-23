import Foundation
import SwiftyJSON

struct Playlist: Identifiable, Equatable, Hashable {
    enum Visibility: String, CaseIterable, Identifiable {
        case `public`, unlisted, `private`

        var id: String {
            rawValue
        }

        var name: String {
            rawValue.capitalized.localized()
        }
    }

    let id: String
    var title: String
    var visibility: Visibility
    var editable = true

    var updated: TimeInterval?

    var videos = [Video]()

    init(
        id: String,
        title: String,
        visibility: Visibility,
        editable: Bool = true,
        updated: TimeInterval? = nil,
        videos: [Video] = []
    ) {
        self.id = id
        self.title = title
        self.visibility = visibility
        self.editable = editable
        self.updated = updated
        self.videos = videos
    }

    var json: JSON {
        [
            "id": id,
            "title": title,
            "visibility": visibility.rawValue,
            "editable": editable ? "editable" : "",
            "updated": updated ?? "",
            "videos": videos.map(\.json).map(\.object)
        ]
    }

    static func from(_ json: JSON) -> Self {
        .init(
            id: json["id"].stringValue,
            title: json["title"].stringValue,
            visibility: .init(rawValue: json["visibility"].stringValue) ?? .public,
            updated: json["updated"].doubleValue,
            videos: json["videos"].arrayValue.map { Video.from($0) }
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.updated == rhs.updated
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var channelPlaylist: ChannelPlaylist {
        ChannelPlaylist(id: id, title: title, videos: videos, videosCount: videos.count)
    }
}
