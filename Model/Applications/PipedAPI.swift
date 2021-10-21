import AVFoundation
import Foundation
import Siesta
import SwiftyJSON

final class PipedAPI: Service, ObservableObject, VideosAPI {
    @Published var account: Account!

    var anonymousAccount: Account {
        .init(instanceID: account.instance.id, name: "Anonymous", url: account.instance.url)
    }

    init(account: Account? = nil) {
        super.init()

        guard account != nil else {
            return
        }

        setAccount(account!)
    }

    func setAccount(_ account: Account) {
        self.account = account

        configure()
    }

    func configure() {
        configure {
            $0.pipeline[.parsing].add(SwiftyJSONTransformer, contentTypes: ["*/json"])
        }

        configureTransformer(pathPattern("channel/*")) { (content: Entity<JSON>) -> Channel? in
            self.extractChannel(content.json)
        }

        configureTransformer(pathPattern("streams/*")) { (content: Entity<JSON>) -> Video? in
            self.extractVideo(content.json)
        }

        configureTransformer(pathPattern("trending")) { (content: Entity<JSON>) -> [Video] in
            self.extractVideos(content.json)
        }

        configureTransformer(pathPattern("search")) { (content: Entity<JSON>) -> [Video] in
            self.extractVideos(content.json.dictionaryValue["items"]!)
        }

        configureTransformer(pathPattern("suggestions")) { (content: Entity<JSON>) -> [String] in
            content.json.arrayValue.map(String.init)
        }
    }

    private func extractChannel(_ content: JSON) -> Channel? {
        Channel(
            id: content.dictionaryValue["id"]!.stringValue,
            name: content.dictionaryValue["name"]!.stringValue,
            subscriptionsCount: content.dictionaryValue["subscriberCount"]!.intValue,
            videos: extractVideos(content.dictionaryValue["relatedStreams"]!)
        )
    }

    private func extractVideo(_ content: JSON) -> Video? {
        let details = content.dictionaryValue
        let url = details["url"]?.string

        if !url.isNil {
            guard url!.contains("/watch") else {
                return nil
            }
        }

        let channelId = details["uploaderUrl"]!.stringValue.components(separatedBy: "/").last!

        let thumbnails: [Thumbnail] = Thumbnail.Quality.allCases.compactMap {
            if let url = buildThumbnailURL(content, quality: $0) {
                return Thumbnail(url: url, quality: $0)
            }

            return nil
        }

        let author = details["uploaderName"]?.stringValue ?? details["uploader"]!.stringValue

        return Video(
            videoID: extractID(content),
            title: details["title"]!.stringValue,
            author: author,
            length: details["duration"]!.doubleValue,
            published: details["uploadedDate"]?.stringValue ?? details["uploadDate"]!.stringValue,
            views: details["views"]!.intValue,
            description: extractDescription(content),
            channel: Channel(id: channelId, name: author),
            thumbnails: thumbnails,
            likes: details["likes"]?.int,
            dislikes: details["dislikes"]?.int,
            streams: extractStreams(content)
        )
    }

    private func extractID(_ content: JSON) -> Video.ID {
        content.dictionaryValue["url"]?.stringValue.components(separatedBy: "?v=").last ??
            extractThumbnailURL(content)!.relativeString.components(separatedBy: "/")[4]
    }

    private func extractThumbnailURL(_ content: JSON) -> URL? {
        content.dictionaryValue["thumbnail"]?.url! ?? content.dictionaryValue["thumbnailUrl"]!.url!
    }

    private func buildThumbnailURL(_ content: JSON, quality: Thumbnail.Quality) -> URL? {
        let thumbnailURL = extractThumbnailURL(content)
        guard !thumbnailURL.isNil else {
            return nil
        }

        return URL(string: thumbnailURL!
            .absoluteString
            .replacingOccurrences(of: "_webp", with: "")
            .replacingOccurrences(of: ".webp", with: ".jpg")
            .replacingOccurrences(of: "hqdefault", with: quality.filename)
            .replacingOccurrences(of: "maxresdefault", with: quality.filename)
        )!
    }

    private func extractDescription(_ content: JSON) -> String? {
        guard var description = content.dictionaryValue["description"]?.string else {
            return nil
        }

        description = description.replacingOccurrences(
            of: "<br/>|<br />|<br>",
            with: "\n",
            options: .regularExpression,
            range: nil
        )

        description = description.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression,
            range: nil
        )

        return description
    }

    private func extractVideos(_ content: JSON) -> [Video] {
        content.arrayValue.compactMap(extractVideo(_:))
    }

    private func extractStreams(_ content: JSON) -> [Stream] {
        var streams = [Stream]()

        if let hlsURL = content.dictionaryValue["hls"]?.url {
            streams.append(Stream(hlsURL: hlsURL))
        }

        guard let audioStream = compatibleAudioStreams(content).first else {
            return streams
        }

        let videoStreams = compatibleVideoStream(content)

        videoStreams.forEach { videoStream in
            let audioAsset = AVURLAsset(url: audioStream.dictionaryValue["url"]!.url!)
            let videoAsset = AVURLAsset(url: videoStream.dictionaryValue["url"]!.url!)

            let videoOnly = videoStream.dictionaryValue["videoOnly"]?.boolValue ?? true
            let resolution = Stream.Resolution.from(resolution: videoStream.dictionaryValue["quality"]!.stringValue)

            if videoOnly {
                streams.append(
                    Stream(audioAsset: audioAsset, videoAsset: videoAsset, resolution: resolution, kind: .adaptive)
                )
            } else {
                streams.append(
                    SingleAssetStream(avAsset: videoAsset, resolution: resolution, kind: .stream)
                )
            }
        }

        return streams
    }

    private func compatibleAudioStreams(_ content: JSON) -> [JSON] {
        content
            .dictionaryValue["audioStreams"]?
            .arrayValue
            .filter { $0.dictionaryValue["format"]?.stringValue == "M4A" }
            .sorted {
                $0.dictionaryValue["bitrate"]?.intValue ?? 0 > $1.dictionaryValue["bitrate"]?.intValue ?? 0
            } ?? []
    }

    private func compatibleVideoStream(_ content: JSON) -> [JSON] {
        content
            .dictionaryValue["videoStreams"]?
            .arrayValue
            .filter { $0.dictionaryValue["format"] == "MPEG_4" } ?? []
    }

    func channel(_ id: String) -> Resource {
        resource(baseURL: account.url, path: "channel/\(id)")
    }

    func trending(country: Country, category _: TrendingCategory? = nil) -> Resource {
        resource(baseURL: account.instance.url, path: "trending")
            .withParam("region", country.rawValue)
    }

    func search(_ query: SearchQuery) -> Resource {
        resource(baseURL: account.instance.url, path: "search")
            .withParam("q", query.query)
            .withParam("filter", "")
    }

    func searchSuggestions(query: String) -> Resource {
        resource(baseURL: account.instance.url, path: "suggestions")
            .withParam("query", query.lowercased())
    }

    func video(_ id: Video.ID) -> Resource {
        resource(baseURL: account.instance.url, path: "streams/\(id)")
    }

    var signedIn: Bool { false }

    var subscriptions: Resource? { nil }
    var feed: Resource? { nil }
    var home: Resource? { nil }
    var popular: Resource? { nil }
    var playlists: Resource? { nil }

    func channelSubscription(_: String) -> Resource? { nil }

    func playlistVideo(_: String, _: String) -> Resource? { nil }
    func playlistVideos(_: String) -> Resource? { nil }

    private func pathPattern(_ path: String) -> String {
        "**\(path)"
    }
}
