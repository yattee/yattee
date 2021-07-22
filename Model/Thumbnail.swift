import Foundation
import SwiftyJSON

struct Thumbnail {
    enum Quality: String, CaseIterable {
        case maxres, maxresdefault, sddefault, high, medium, `default`, start, middle, end
    }

    var url: URL
    var quality: Quality

    init(_ json: JSON) {
        url = json["url"].url!
        quality = Quality(rawValue: json["quality"].string!)!
    }

    init(url: URL, quality: Quality) {
        self.url = url
        self.quality = quality
    }
}
