import AVFoundation
import Defaults
import Foundation
import SwiftyJSON

struct Channel: Identifiable, Hashable {
    var id: String
    var name: String
    var videos = [Video]()

    private var subscriptionsCount: Int?
    private var subscriptionsText: String?

    init(json: JSON) {
        id = json["authorId"].stringValue
        name = json["author"].stringValue
        subscriptionsCount = json["subCount"].int
        subscriptionsText = json["subCountText"].string

        if let channelVideos = json.dictionaryValue["latestVideos"] {
            videos = channelVideos.arrayValue.map(Video.init)
        }
    }

    init(id: String, name: String, subscriptionsCount: Int? = nil, videos: [Video] = []) {
        self.id = id
        self.name = name
        self.subscriptionsCount = subscriptionsCount
        self.videos = videos
    }

    var subscriptionsString: String? {
        if subscriptionsCount != nil {
            return subscriptionsCount!.formattedAsAbbreviation()
        }

        return subscriptionsText
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
