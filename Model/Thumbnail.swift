import Foundation
import SwiftyJSON

struct Thumbnail {
    var url: URL
    var quality: String

    init(_ json: JSON) {
        url = json["url"].url!
        quality = json["quality"].string!
    }
}
