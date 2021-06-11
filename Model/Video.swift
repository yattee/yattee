import Alamofire
import Foundation
import SwiftyJSON

final class Video: Identifiable, ObservableObject {
    let id: String
    var title: String
    var thumbnailURL: URL
    var author: String
    var length: TimeInterval
    var published: String
    var views: Int

    @Published var url: URL?
    @Published var error: Bool = false

    init(id: String, title: String, thumbnailURL: URL, author: String, length: TimeInterval, published: String, views: Int = 0) {
        self.id = id
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.author = author
        self.length = length
        self.published = published
        self.views = views
    }

    init(_ json: JSON) {
        func extractThumbnailURL(from details: JSON) -> URL {
            if details["videoThumbnails"].arrayValue.isEmpty {
                return URL(string: "https://invidious.home.arekf.net/vi/LuKwJyBNBsE/maxres.jpg")!
            }
            
            return details["videoThumbnails"][0]["url"].url!
        }
        
        func extractFormatStreamURL(from streams: [JSON]) -> URL? {
            if streams.isEmpty {
                error = true
                return nil
            }

            let stream = streams.last!

            return stream["url"].url
        }
        
        id = json["videoId"].stringValue
        title = json["title"].stringValue
        thumbnailURL = extractThumbnailURL(from: json)
        author = json["author"].stringValue
        length = json["lengthSeconds"].doubleValue
        published = json["publishedText"].stringValue
        views = json["viewCount"].intValue

        url = extractFormatStreamURL(from: json["formatStreams"].arrayValue)
    }

    var playTime: String? {
        let formatter = DateComponentsFormatter()

        formatter.unitsStyle = .positional
        formatter.allowedUnits = length >= (60 * 60) ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]

        return formatter.string(from: length)
    }

    var viewsCount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1

        var number: NSNumber
        var unit: String

        if views < 1_000_000 {
            number = NSNumber(value: Double(views) / 1000.0)
            unit = "K"
        } else {
            number = NSNumber(value: Double(views) / 1_000_000.0)
            unit = "M"
        }

        return "\(formatter.string(from: number)!)\(unit)"
    }
}
