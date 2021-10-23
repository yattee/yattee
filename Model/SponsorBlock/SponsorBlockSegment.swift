import Foundation
import SwiftyJSON

final class SponsorBlockSegment: Segment {
    init(_ json: JSON) {
        super.init(
            category: json["category"].string!,
            segment: json["segment"].array!.map { $0.double! },
            uuid: json["UUID"].string!,
            videoDuration: json["videoDuration"].int!
        )
    }

    override func title() -> String {
        switch category {
        case "selfpromo":
            return "self-promotion"
        case "music_offtopic":
            return "offtopic"
        default:
            return category
        }
    }
}
