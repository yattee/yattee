import Alamofire
import Foundation
import SwiftyJSON

class Video: Identifiable, ObservableObject {
    let id: String
    var title: String
    var thumbnailURL: URL
    var author: String

    @Published var url: URL?
    @Published var error: Bool = false

    init(id: String, title: String, thumbnailURL: URL, author: String) {
        self.id = id
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.author = author
    }

    init(_ json: JSON) {
        id = json["videoId"].stringValue
        title = json["title"].stringValue
        thumbnailURL = json["videoThumbnails"][0]["url"].url!
        author = json["author"].stringValue
        url = formatStreamURL(from: json["formatStreams"].arrayValue)
    }

    func formatStreamURL(from streams: [JSON]) -> URL? {
        if streams.isEmpty {
            error = true
            return nil
        }

        let stream = streams.last!

        return stream["url"].url
    }
}
