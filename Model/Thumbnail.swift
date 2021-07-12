import Foundation
import SwiftyJSON

struct Thumbnail {
    var url: URL
    var quality: ThumbnailQuality

    init(_ json: JSON) {
        url = json["url"].url!
        quality = ThumbnailQuality(rawValue: json["quality"].string!)!
    }
}
