import AVFoundation
import Foundation
import Siesta
import SwiftyJSON

final class PipedAPI: Service, ObservableObject, VideosAPI {
    static var authorizedEndpoints = ["subscriptions", "subscribe", "unsubscribe"]

    @Published var account: Account!

    var anonymousAccount: Account {
        .init(instanceID: account.instance.id, name: "Anonymous", url: account.instance.apiURL)
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
        invalidateConfiguration()

        configure {
            $0.pipeline[.parsing].add(SwiftyJSONTransformer, contentTypes: ["*/json"])
        }

        configure(whenURLMatches: { url in self.needsAuthorization(url) }) {
            $0.headers["Authorization"] = self.account.token
        }

        configureTransformer(pathPattern("channel/*")) { (content: Entity<JSON>) -> Channel? in
            PipedAPI.extractChannel(from: content.json)
        }

        configureTransformer(pathPattern("playlists/*")) { (content: Entity<JSON>) -> ChannelPlaylist? in
            PipedAPI.extractChannelPlaylist(from: content.json)
        }

        configureTransformer(pathPattern("streams/*")) { (content: Entity<JSON>) -> Video? in
            PipedAPI.extractVideo(from: content.json)
        }

        configureTransformer(pathPattern("trending")) { (content: Entity<JSON>) -> [Video] in
            PipedAPI.extractVideos(from: content.json)
        }

        configureTransformer(pathPattern("search")) { (content: Entity<JSON>) -> [ContentItem] in
            PipedAPI.extractContentItems(from: content.json.dictionaryValue["items"]!)
        }

        configureTransformer(pathPattern("suggestions")) { (content: Entity<JSON>) -> [String] in
            content.json.arrayValue.map(String.init)
        }

        configureTransformer(pathPattern("subscriptions")) { (content: Entity<JSON>) -> [Channel] in
            content.json.arrayValue.map { PipedAPI.extractChannel(from: $0)! }
        }

        configureTransformer(pathPattern("feed")) { (content: Entity<JSON>) -> [Video] in
            content.json.arrayValue.map { PipedAPI.extractVideo(from: $0)! }
        }

        if account.token.isNil {
            updateToken()
        }
    }

    func needsAuthorization(_ url: URL) -> Bool {
        PipedAPI.authorizedEndpoints.contains { url.absoluteString.contains($0) }
    }

    @discardableResult func updateToken() -> Request {
        account.token = nil
        return login.request(
            .post,
            json: ["username": account.username, "password": account.password]
        )
        .onSuccess { response in
            self.account.token = response.json.dictionaryValue["token"]?.string ?? ""
            self.configure()
        }
    }

    var login: Resource {
        resource(baseURL: account.url, path: "login")
    }

    func channel(_ id: String) -> Resource {
        resource(baseURL: account.url, path: "channel/\(id)")
    }

    func channelVideos(_ id: String) -> Resource {
        channel(id)
    }

    func channelPlaylist(_ id: String) -> Resource? {
        resource(baseURL: account.url, path: "playlists/\(id)")
    }

    func trending(country: Country, category _: TrendingCategory? = nil) -> Resource {
        resource(baseURL: account.instance.apiURL, path: "trending")
            .withParam("region", country.rawValue)
    }

    func search(_ query: SearchQuery) -> Resource {
        resource(baseURL: account.instance.apiURL, path: "search")
            .withParam("q", query.query)
            .withParam("filter", "")
    }

    func searchSuggestions(query: String) -> Resource {
        resource(baseURL: account.instance.apiURL, path: "suggestions")
            .withParam("query", query.lowercased())
    }

    func video(_ id: Video.ID) -> Resource {
        resource(baseURL: account.instance.apiURL, path: "streams/\(id)")
    }

    var signedIn: Bool {
        !account.anonymous && !(account.token?.isEmpty ?? true)
    }

    var subscriptions: Resource? {
        resource(baseURL: account.instance.apiURL, path: "subscriptions")
    }

    var feed: Resource? {
        resource(baseURL: account.instance.apiURL, path: "feed")
            .withParam("authToken", account.token)
    }

    var home: Resource? { nil }
    var popular: Resource? { nil }
    var playlists: Resource? { nil }

    func subscribe(_ channelID: String, onCompletion: @escaping () -> Void = {}) {
        resource(baseURL: account.instance.apiURL, path: "subscribe")
            .request(.post, json: ["channelId": channelID])
            .onCompletion { _ in onCompletion() }
    }

    func unsubscribe(_ channelID: String, onCompletion: @escaping () -> Void = {}) {
        resource(baseURL: account.instance.apiURL, path: "unsubscribe")
            .request(.post, json: ["channelId": channelID])
            .onCompletion { _ in onCompletion() }
    }

    func playlist(_: String) -> Resource? { nil }
    func playlistVideo(_: String, _: String) -> Resource? { nil }
    func playlistVideos(_: String) -> Resource? { nil }

    private func pathPattern(_ path: String) -> String {
        "**\(path)"
    }

    private static func extractContentItem(from content: JSON) -> ContentItem? {
        let details = content.dictionaryValue
        let url: String! = details["url"]?.string

        let contentType: ContentItem.ContentType

        if !url.isNil {
            if url.contains("/playlist") {
                contentType = .playlist
            } else if url.contains("/channel") {
                contentType = .channel
            } else {
                contentType = .video
            }
        } else {
            contentType = .video
        }

        switch contentType {
        case .video:
            if let video = PipedAPI.extractVideo(from: content) {
                return ContentItem(video: video)
            }

        case .playlist:
            if let playlist = PipedAPI.extractChannelPlaylist(from: content) {
                return ContentItem(playlist: playlist)
            }

        case .channel:
            if let channel = PipedAPI.extractChannel(from: content) {
                return ContentItem(channel: channel)
            }
        }

        return nil
    }

    private static func extractContentItems(from content: JSON) -> [ContentItem] {
        content.arrayValue.compactMap { PipedAPI.extractContentItem(from: $0) }
    }

    private static func extractChannel(from content: JSON) -> Channel? {
        let attributes = content.dictionaryValue
        guard let id = attributes["id"]?.stringValue ??
            (attributes["url"] ?? attributes["uploaderUrl"])?.stringValue.components(separatedBy: "/").last
        else {
            return nil
        }

        let subscriptionsCount = attributes["subscriberCount"]?.intValue ?? attributes["subscribers"]?.intValue

        var videos = [Video]()
        if let relatedStreams = attributes["relatedStreams"] {
            videos = PipedAPI.extractVideos(from: relatedStreams)
        }

        return Channel(
            id: id,
            name: attributes["name"]!.stringValue,
            thumbnailURL: attributes["thumbnail"]?.url,
            subscriptionsCount: subscriptionsCount,
            videos: videos
        )
    }

    static func extractChannelPlaylist(from json: JSON) -> ChannelPlaylist? {
        let details = json.dictionaryValue
        let id = details["url"]?.stringValue.components(separatedBy: "?list=").last ?? UUID().uuidString
        let thumbnailURL = details["thumbnail"]?.url ?? details["thumbnailUrl"]?.url
        var videos = [Video]()
        if let relatedStreams = details["relatedStreams"] {
            videos = PipedAPI.extractVideos(from: relatedStreams)
        }
        return ChannelPlaylist(
            id: id,
            title: details["name"]!.stringValue,
            thumbnailURL: thumbnailURL,
            channel: extractChannel(from: json)!,
            videos: videos,
            videosCount: details["videos"]?.int
        )
    }

    private static func extractVideo(from content: JSON) -> Video? {
        let details = content.dictionaryValue
        let url = details["url"]?.string

        if !url.isNil {
            guard url!.contains("/watch") else {
                return nil
            }
        }

        let channelId = details["uploaderUrl"]!.stringValue.components(separatedBy: "/").last!

        let thumbnails: [Thumbnail] = Thumbnail.Quality.allCases.compactMap {
            if let url = PipedAPI.buildThumbnailURL(from: content, quality: $0) {
                return Thumbnail(url: url, quality: $0)
            }

            return nil
        }

        let author = details["uploaderName"]?.stringValue ?? details["uploader"]!.stringValue
        let published = (details["uploadedDate"] ?? details["uploadDate"])?.stringValue ??
            (details["uploaded"]!.double! / 1000).formattedAsRelativeTime()!

        return Video(
            videoID: PipedAPI.extractID(from: content),
            title: details["title"]!.stringValue,
            author: author,
            length: details["duration"]!.doubleValue,
            published: published,
            views: details["views"]!.intValue,
            description: PipedAPI.extractDescription(from: content),
            channel: Channel(id: channelId, name: author),
            thumbnails: thumbnails,
            likes: details["likes"]?.int,
            dislikes: details["dislikes"]?.int,
            streams: extractStreams(from: content),
            related: extractRelated(from: content)
        )
    }

    private static func extractID(from content: JSON) -> Video.ID {
        content.dictionaryValue["url"]?.stringValue.components(separatedBy: "?v=").last ??
            extractThumbnailURL(from: content)!.relativeString.components(separatedBy: "/")[4]
    }

    private static func extractThumbnailURL(from content: JSON) -> URL? {
        content.dictionaryValue["thumbnail"]?.url! ?? content.dictionaryValue["thumbnailUrl"]!.url!
    }

    private static func buildThumbnailURL(from content: JSON, quality: Thumbnail.Quality) -> URL? {
        let thumbnailURL = extractThumbnailURL(from: content)
        guard !thumbnailURL.isNil else {
            return nil
        }

        return URL(string: thumbnailURL!
            .absoluteString
            .replacingOccurrences(of: "hqdefault", with: quality.filename)
            .replacingOccurrences(of: "maxresdefault", with: quality.filename)
        )!
    }

    private static func extractDescription(from content: JSON) -> String? {
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

    private static func extractVideos(from content: JSON) -> [Video] {
        content.arrayValue.compactMap(extractVideo(from:))
    }

    private static func extractStreams(from content: JSON) -> [Stream] {
        var streams = [Stream]()

        if let hlsURL = content.dictionaryValue["hls"]?.url {
            streams.append(Stream(hlsURL: hlsURL))
        }

        guard let audioStream = PipedAPI.compatibleAudioStreams(from: content).first else {
            return streams
        }

        let videoStreams = PipedAPI.compatibleVideoStream(from: content)

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

    private static func extractRelated(from content: JSON) -> [Video] {
        content
            .dictionaryValue["relatedStreams"]?
            .arrayValue
            .compactMap(extractVideo(from:)) ?? []
    }

    private static func compatibleAudioStreams(from content: JSON) -> [JSON] {
        content
            .dictionaryValue["audioStreams"]?
            .arrayValue
            .filter { $0.dictionaryValue["format"]?.stringValue == "M4A" }
            .sorted {
                $0.dictionaryValue["bitrate"]?.intValue ?? 0 > $1.dictionaryValue["bitrate"]?.intValue ?? 0
            } ?? []
    }

    private static func compatibleVideoStream(from content: JSON) -> [JSON] {
        content
            .dictionaryValue["videoStreams"]?
            .arrayValue
            .filter { $0.dictionaryValue["format"] == "MPEG_4" } ?? []
    }
}
