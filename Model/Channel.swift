import AVFoundation
import Defaults
import Foundation
import SwiftyJSON

struct Channel: Codable, Defaults.Serializable {
    var id: String
    var name: String
    var subscriptionsCount: String

    init(json: JSON) {
        id = json["authorId"].stringValue
        name = json["author"].stringValue
        subscriptionsCount = json["subCountText"].stringValue
    }

    init(id: String, name: String, subscriptionsCount: String) {
        self.id = id
        self.name = name
        self.subscriptionsCount = subscriptionsCount
    }
}
