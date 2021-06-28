import Foundation
import SwiftyJSON

struct Playlist: Identifiable, Equatable, Hashable {
    let id: String
    var title: String
    var description: String

    var videos = [Video]()

    init(_ json: JSON) {
        id = json["playlistId"].stringValue
        title = json["title"].stringValue
        description = json["description"].stringValue
        videos = json["videos"].arrayValue.map { Video($0) }
    }

    static func == (lhs: Playlist, rhs: Playlist) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
