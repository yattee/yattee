import AVFoundation
import Foundation
import Siesta
import SwiftyJSON

final class PipedAPI: Service, ObservableObject, VideosAPI {
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

    private func wrapHttpBasicAuthToURL(url: URL?) -> URL? {
        if url == nil {
            return nil
        }
        var parsedURL = URLComponents(string: url!.absoluteString)
        parsedURL?.user = self.account.instance.username
        parsedURL?.password = self.account.instance.password
        return try! parsedURL?.asURL()
    }

    private func wrapHttpBasicAuthToURL(string: String?) -> String? {
        if string == nil {
            return nil
        }
        var parsedURL = URLComponents(string: string!)
        parsedURL?.user = self.account.instance.username
        parsedURL?.password = self.account.instance.password
        return try! parsedURL?.asURL().absoluteString
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
            self.extractChannel(from: content.json)
        }

        configureTransformer(pathPattern("playlists/*")) { (content: Entity<JSON>) -> ChannelPlaylist? in
            self.extractChannelPlaylist(from: content.json)
        }

        configureTransformer(pathPattern("streams/*")) { (content: Entity<JSON>) -> Video? in
            self.extractVideo(from: content.json)
        }

        configureTransformer(pathPattern("trending")) { (content: Entity<JSON>) -> [Video] in
            self.extractVideos(from: content.json)
        }

        configureTransformer(pathPattern("search")) { (content: Entity<JSON>) -> [ContentItem] in
            self.extractContentItems(from: content.json.dictionaryValue["items"]!)
        }

        configureTransformer(pathPattern("suggestions")) { (content: Entity<JSON>) -> [String] in
            content.json.arrayValue.map(String.init)
        }
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

    var signedIn: Bool { false }

    var subscriptions: Resource? { nil }
    var feed: Resource? { nil }
    var home: Resource? { nil }
    var popular: Resource? { nil }
    var playlists: Resource? { nil }

    func channelSubscription(_: String) -> Resource? { nil }

    func playlist(_: String) -> Resource? { nil }
    func playlistVideo(_: String, _: String) -> Resource? { nil }
    func playlistVideos(_: String) -> Resource? { nil }

    private func pathPattern(_ path: String) -> String {
        "**\(path)"
    }

    private func extractContentItem(from content: JSON) -> ContentItem? {
        let details = content.dictionaryValue
        let url: String! = self.wrapHttpBasicAuthToURL(string: details["url"]?.string)

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
            if let video = self.extractVideo(from: content) {
                return ContentItem(video: video)
            }

        case .playlist:
            if let playlist = self.extractChannelPlaylist(from: content) {
                return ContentItem(playlist: playlist)
            }

        case .channel:
            if let channel = self.extractChannel(from: content) {
                return ContentItem(channel: channel)
            }
        }

        return nil
    }

    private func extractContentItems(from content: JSON) -> [ContentItem] {
        content.arrayValue.compactMap { self.extractContentItem(from: $0) }
    }

    private func extractChannel(from content: JSON) -> Channel? {
        let attributes = content.dictionaryValue
        guard let id = attributes["id"]?.stringValue ??
            (attributes["url"] ?? attributes["uploaderUrl"])?.stringValue.components(separatedBy: "/").last
        else {
            return nil
        }

        let subscriptionsCount = attributes["subscriberCount"]?.intValue ?? attributes["subscribers"]?.intValue

        var videos = [Video]()
        if let relatedStreams = attributes["relatedStreams"] {
            videos = self.extractVideos(from: relatedStreams)
        }

        return Channel(
            id: id,
            name: attributes["name"]!.stringValue,
            thumbnailURL: self.wrapHttpBasicAuthToURL(url: attributes["thumbnail"]?.url),
            subscriptionsCount: subscriptionsCount,
            videos: videos
        )
    }

    func extractChannelPlaylist(from json: JSON) -> ChannelPlaylist? {
        let details = json.dictionaryValue
        let id = details["url"]?.stringValue.components(separatedBy: "?list=").last ?? UUID().uuidString
        let thumbnailURL = details["thumbnail"]?.url ?? details["thumbnailUrl"]?.url
        var videos = [Video]()
        if let relatedStreams = details["relatedStreams"] {
            videos = self.extractVideos(from: relatedStreams)
        }
        return ChannelPlaylist(
            id: id,
            title: details["name"]!.stringValue,
            thumbnailURL: self.wrapHttpBasicAuthToURL(url: thumbnailURL),
            channel: extractChannel(from: json)!,
            videos: videos,
            videosCount: details["videos"]?.int
        )
    }

    private func extractVideo(from content: JSON) -> Video? {
        let details = content.dictionaryValue
        let url = details["url"]?.string

        if !url.isNil {
            guard url!.contains("/watch") else {
                return nil
            }
        }

        let channelId = details["uploaderUrl"]!.stringValue.components(separatedBy: "/").last!

        let thumbnails: [Thumbnail] = Thumbnail.Quality.allCases.compactMap {
            if let url = self.buildThumbnailURL(from: content, quality: $0) {
                return Thumbnail(url: self.wrapHttpBasicAuthToURL(url: url)!, quality: $0)
            }

            return nil
        }

        let author = details["uploaderName"]?.stringValue ?? details["uploader"]!.stringValue

        return Video(
            videoID: self.extractID(from: content),
            title: details["title"]!.stringValue,
            author: author,
            length: details["duration"]!.doubleValue,
            published: details["uploadedDate"]?.stringValue ?? details["uploadDate"]!.stringValue,
            views: details["views"]!.intValue,
            description: self.extractDescription(from: content),
            channel: Channel(id: channelId, name: author),
            thumbnails: thumbnails,
            likes: details["likes"]?.int,
            dislikes: details["dislikes"]?.int,
            streams: extractStreams(from: content),
            related: extractRelated(from: content)
        )
    }

    private func extractID(from content: JSON) -> Video.ID {
        var fromThumbnailUrl = extractThumbnailURL(from: content)!.relativeString.components(separatedBy: "/")
        fromThumbnailUrl.removeLast()
        return content.dictionaryValue["url"]?.stringValue.components(separatedBy: "?v=").last ?? fromThumbnailUrl.last!
    }

    private func extractThumbnailURL(from content: JSON) -> URL? {
        let url = content.dictionaryValue["thumbnail"]?.url! ?? content.dictionaryValue["thumbnailUrl"]!.url!

        return self.wrapHttpBasicAuthToURL(url: url)
    }

    private func buildThumbnailURL(from content: JSON, quality: Thumbnail.Quality) -> URL? {
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

    private func extractDescription(from content: JSON) -> String? {
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

    private func extractVideos(from content: JSON) -> [Video] {
        content.arrayValue.compactMap(extractVideo(from:))
    }

    private func extractStreams(from content: JSON) -> [Stream] {
        var streams = [Stream]()

        if let hlsURL = content.dictionaryValue["hls"]?.url {
            let hlsURLWrapped = self.wrapHttpBasicAuthToURL(url: hlsURL)
            streams.append(Stream(hlsURL: hlsURLWrapped))
        }

        guard let audioStream = self.compatibleAudioStreams(from: content).first else {
            return streams
        }

        let videoStreams = self.compatibleVideoStream(from: content)

        videoStreams.forEach { videoStream in
            let audioAsset = AVURLAsset(url: self.wrapHttpBasicAuthToURL(url: audioStream.dictionaryValue["url"]!.url)!)
            let videoAsset = AVURLAsset(url: self.wrapHttpBasicAuthToURL(url: videoStream.dictionaryValue["url"]!.url)!)

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

    private func extractRelated(from content: JSON) -> [Video] {
        content
            .dictionaryValue["relatedStreams"]?
            .arrayValue
            .compactMap(extractVideo(from:)) ?? []
    }

    private func compatibleAudioStreams(from content: JSON) -> [JSON] {
        content
            .dictionaryValue["audioStreams"]?
            .arrayValue
            .filter { $0.dictionaryValue["format"]?.stringValue == "M4A" }
            .sorted {
                $0.dictionaryValue["bitrate"]?.intValue ?? 0 > $1.dictionaryValue["bitrate"]?.intValue ?? 0
            } ?? []
    }

    private func compatibleVideoStream(from content: JSON) -> [JSON] {
        content
            .dictionaryValue["videoStreams"]?
            .arrayValue
            .filter { $0.dictionaryValue["format"] == "MPEG_4" } ?? []
    }
}
