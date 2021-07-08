import Foundation
import SwiftyJSON

struct Playlist: Identifiable, Equatable, Hashable {
    let id: String
    var title: String
    var visibility: PlaylistVisibility

    var videos = [Video]()

    init(_ json: JSON) {
        id = json["playlistId"].stringValue
        title = json["title"].stringValue
        visibility = json["isListed"].boolValue ? .public : .private
        videos = json["videos"].arrayValue.map { Video($0) }
    }

    static func == (lhs: Playlist, rhs: Playlist) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.visibility == rhs.visibility
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
