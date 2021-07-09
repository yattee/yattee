import Foundation
import SwiftyJSON

struct Playlist: Identifiable, Equatable, Hashable {
    let id: String
    var title: String
    var visibility: PlaylistVisibility

    var updated: TimeInterval

    var videos = [Video]()

    init(_ json: JSON) {
        id = json["playlistId"].stringValue
        title = json["title"].stringValue
        visibility = json["isListed"].boolValue ? .public : .private
        updated = json["updated"].doubleValue
        videos = json["videos"].arrayValue.map { Video($0) }
    }

    static func == (lhs: Playlist, rhs: Playlist) -> Bool {
        lhs.id == rhs.id && lhs.updated == rhs.updated
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
