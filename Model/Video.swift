import Alamofire
import AVKit
import Foundation
import SwiftyJSON

final class Video: Identifiable, ObservableObject {
    let id: String
    var title: String
    var thumbnailURL: URL?
    var author: String
    var length: TimeInterval
    var published: String
    var views: Int
    var channelID: String
    var description: String
    var genre: String

    var streams = [Stream]()

    init(_ json: JSON) {
        id = json["videoId"].stringValue
        title = json["title"].stringValue
        author = json["author"].stringValue
        length = json["lengthSeconds"].doubleValue
        published = json["publishedText"].stringValue
        views = json["viewCount"].intValue
        channelID = json["authorId"].stringValue
        description = json["description"].stringValue
        genre = json["genre"].stringValue

        thumbnailURL = extractThumbnailURL(from: json)

        streams = extractFormatStreams(from: json["formatStreams"].arrayValue)
        streams.append(contentsOf: extractAdaptiveFormats(from: json["adaptiveFormats"].arrayValue))
    }

    var playTime: String? {
        guard !length.isZero else {
            return nil
        }

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

    var selectableStreams: [Stream] {
        let streams = streams.sorted { $0.resolution > $1.resolution }
        var selectable = [Stream]()

        StreamResolution.allCases.forEach { resolution in
            if let stream = streams.filter({ $0.resolution == resolution }).min(by: { $0.type < $1.type }) {
                selectable.append(stream)
            }
        }

        return selectable
    }

    var defaultStream: Stream? {
        selectableStreams.first { $0.type == .stream }
    }

    var bestStream: Stream? {
        selectableStreams.min { $0.resolution > $1.resolution }
    }

    func streamWithResolution(_ resolution: StreamResolution) -> Stream? {
        selectableStreams.first { $0.resolution == resolution }
    }

    func defaultStreamForProfile(_ profile: Profile) -> Stream? {
        streamWithResolution(profile.defaultStreamResolution.value)
    }

    private func extractThumbnailURL(from details: JSON) -> URL? {
        if details["videoThumbnails"].arrayValue.isEmpty {
            return nil
        }

        let thumbnail = details["videoThumbnails"].arrayValue.first { $0["quality"].stringValue == "medium" }!
        return thumbnail["url"].url!
    }

    private func extractFormatStreams(from streams: [JSON]) -> [Stream] {
        streams.map {
            AudioVideoStream(
                avAsset: AVURLAsset(url: DataProvider.proxyURLForAsset($0["url"].stringValue)!),
                resolution: StreamResolution.from(resolution: $0["resolution"].stringValue)!,
                type: .stream,
                encoding: $0["encoding"].stringValue
            )
        }
    }

    private func extractAdaptiveFormats(from streams: [JSON]) -> [Stream] {
        let audioAssetURL = streams.first { $0["type"].stringValue.starts(with: "audio/mp4") }
        guard audioAssetURL != nil else {
            return []
        }

        let videoAssetsURLs = streams.filter { $0["type"].stringValue.starts(with: "video/mp4") && $0["encoding"].stringValue == "h264" }

        return videoAssetsURLs.map {
            Stream(
                audioAsset: AVURLAsset(url: DataProvider.proxyURLForAsset(audioAssetURL!["url"].stringValue)!),
                videoAsset: AVURLAsset(url: DataProvider.proxyURLForAsset($0["url"].stringValue)!),
                resolution: StreamResolution.from(resolution: $0["resolution"].stringValue)!,
                type: .adaptive,
                encoding: $0["encoding"].stringValue
            )
        }
    }
}
