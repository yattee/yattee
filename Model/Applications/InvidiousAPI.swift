import AVKit
import Defaults
import Foundation
import Siesta
import SwiftyJSON

final class InvidiousAPI: Service, ObservableObject, VideosAPI {
    static let basePath = "/api/v1"

    @Published var account: Account!

    @Published var validInstance = true
    @Published var signedIn = false

    init(account: Account? = nil) {
        super.init()

        guard !account.isNil else {
            self.account = .init(name: "Empty")
            return
        }

        setAccount(account!)
    }

    func setAccount(_ account: Account) {
        self.account = account

        validInstance = false
        signedIn = false

        configure()
        validate()
    }

    func validate() {
        validateInstance()
        validateSID()
    }

    func validateInstance() {
        guard !validInstance else {
            return
        }

        home?
            .load()
            .onSuccess { _ in
                self.validInstance = true
            }
            .onFailure { _ in
                self.validInstance = false
            }
    }

    func validateSID() {
        guard !signedIn else {
            return
        }

        feed?
            .load()
            .onSuccess { _ in
                self.signedIn = true
            }
            .onFailure { _ in
                self.signedIn = false
            }
    }

    func configure() {
        configure {
            if !self.account.sid.isEmpty {
                $0.headers["Cookie"] = self.cookieHeader
            }
            $0.pipeline[.parsing].add(SwiftyJSONTransformer, contentTypes: ["*/json"])
        }

        configure("**", requestMethods: [.post]) {
            $0.pipeline[.parsing].removeTransformers()
        }

        configureTransformer(pathPattern("popular"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Video] in
            content.json.arrayValue.map(InvidiousAPI.extractVideo)
        }

        configureTransformer(pathPattern("trending"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Video] in
            content.json.arrayValue.map(InvidiousAPI.extractVideo)
        }

        configureTransformer(pathPattern("search"), requestMethods: [.get]) { (content: Entity<JSON>) -> [ContentItem] in
            content.json.arrayValue.map {
                let type = $0.dictionaryValue["type"]?.stringValue

                if type == "channel" {
                    return ContentItem(channel: InvidiousAPI.extractChannel(from: $0))
                } else if type == "playlist" {
                    return ContentItem(playlist: InvidiousAPI.extractChannelPlaylist(from: $0))
                }
                return ContentItem(video: InvidiousAPI.extractVideo(from: $0))
            }
        }

        configureTransformer(pathPattern("search/suggestions"), requestMethods: [.get]) { (content: Entity<JSON>) -> [String] in
            if let suggestions = content.json.dictionaryValue["suggestions"] {
                return suggestions.arrayValue.map(String.init)
            }

            return []
        }

        configureTransformer(pathPattern("auth/playlists"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Playlist] in
            content.json.arrayValue.map(Playlist.init)
        }

        configureTransformer(pathPattern("auth/playlists/*"), requestMethods: [.get]) { (content: Entity<JSON>) -> Playlist in
            Playlist(content.json)
        }

        configureTransformer(pathPattern("auth/playlists"), requestMethods: [.post, .patch]) { (content: Entity<Data>) -> Playlist in
            // hacky, to verify if possible to get it in easier way
            Playlist(JSON(parseJSON: String(data: content.content, encoding: .utf8)!))
        }

        configureTransformer(pathPattern("auth/feed"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Video] in
            if let feedVideos = content.json.dictionaryValue["videos"] {
                return feedVideos.arrayValue.map(InvidiousAPI.extractVideo)
            }

            return []
        }

        configureTransformer(pathPattern("auth/subscriptions"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Channel] in
            content.json.arrayValue.map(InvidiousAPI.extractChannel)
        }

        configureTransformer(pathPattern("channels/*"), requestMethods: [.get]) { (content: Entity<JSON>) -> Channel in
            InvidiousAPI.extractChannel(from: content.json)
        }

        configureTransformer(pathPattern("channels/*/latest"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Video] in
            content.json.arrayValue.map(InvidiousAPI.extractVideo)
        }

        configureTransformer(pathPattern("playlists/*"), requestMethods: [.get]) { (content: Entity<JSON>) -> ChannelPlaylist in
            InvidiousAPI.extractChannelPlaylist(from: content.json)
        }

        configureTransformer(pathPattern("videos/*"), requestMethods: [.get]) { (content: Entity<JSON>) -> Video in
            InvidiousAPI.extractVideo(from: content.json)
        }
    }

    private func pathPattern(_ path: String) -> String {
        "**\(InvidiousAPI.basePath)/\(path)"
    }

    private func basePathAppending(_ path: String) -> String {
        "\(InvidiousAPI.basePath)/\(path)"
    }

    private var cookieHeader: String {
        "SID=\(account.sid)"
    }

    var popular: Resource? {
        resource(baseURL: account.url, path: "\(InvidiousAPI.basePath)/popular")
    }

    func trending(country: Country, category: TrendingCategory?) -> Resource {
        resource(baseURL: account.url, path: "\(InvidiousAPI.basePath)/trending")
            .withParam("type", category!.name)
            .withParam("region", country.rawValue)
    }

    var home: Resource? {
        resource(baseURL: account.url, path: "/feed/subscriptions")
    }

    var feed: Resource? {
        resource(baseURL: account.url, path: "\(InvidiousAPI.basePath)/auth/feed")
    }

    var subscriptions: Resource? {
        resource(baseURL: account.url, path: basePathAppending("auth/subscriptions"))
    }

    func channelSubscription(_ id: String) -> Resource? {
        resource(baseURL: account.url, path: basePathAppending("auth/subscriptions")).child(id)
    }

    func channel(_ id: String) -> Resource {
        resource(baseURL: account.url, path: basePathAppending("channels/\(id)"))
    }

    func channelVideos(_ id: String) -> Resource {
        resource(baseURL: account.url, path: basePathAppending("channels/\(id)/latest"))
    }

    func video(_ id: String) -> Resource {
        resource(baseURL: account.url, path: basePathAppending("videos/\(id)"))
    }

    var playlists: Resource? {
        resource(baseURL: account.url, path: basePathAppending("auth/playlists"))
    }

    func playlist(_ id: String) -> Resource? {
        resource(baseURL: account.url, path: basePathAppending("auth/playlists/\(id)"))
    }

    func playlistVideos(_ id: String) -> Resource? {
        playlist(id)?.child("videos")
    }

    func playlistVideo(_ playlistID: String, _ videoID: String) -> Resource? {
        playlist(playlistID)?.child("videos").child(videoID)
    }

    func channelPlaylist(_ id: String) -> Resource? {
        resource(baseURL: account.url, path: basePathAppending("playlists/\(id)"))
    }

    func search(_ query: SearchQuery) -> Resource {
        var resource = resource(baseURL: account.url, path: basePathAppending("search"))
            .withParam("q", searchQuery(query.query))
            .withParam("sort_by", query.sortBy.parameter)
            .withParam("type", "all")

        if let date = query.date, date != .any {
            resource = resource.withParam("date", date.rawValue)
        }

        if let duration = query.duration, duration != .any {
            resource = resource.withParam("duration", duration.rawValue)
        }

        return resource
    }

    func searchSuggestions(query: String) -> Resource {
        resource(baseURL: account.url, path: basePathAppending("search/suggestions"))
            .withParam("q", query.lowercased())
    }

    private func searchQuery(_ query: String) -> String {
        var searchQuery = query

        let url = URLComponents(string: query)

        if url != nil,
           url!.host == "youtu.be"
        {
            searchQuery = url!.path.replacingOccurrences(of: "/", with: "")
        }

        let queryItem = url?.queryItems?.first { item in item.name == "v" }
        if let id = queryItem?.value {
            searchQuery = id
        }

        return searchQuery
    }

    static func proxiedAsset(instance: Instance, asset: AVURLAsset) -> AVURLAsset? {
        guard let instanceURLComponents = URLComponents(string: instance.url),
              var urlComponents = URLComponents(url: asset.url, resolvingAgainstBaseURL: false) else { return nil }

        urlComponents.scheme = instanceURLComponents.scheme
        urlComponents.host = instanceURLComponents.host

        guard let url = urlComponents.url else {
            return nil
        }

        return AVURLAsset(url: url)
    }

    static func extractVideo(from json: JSON) -> Video {
        let indexID: String?
        var id: Video.ID
        var publishedAt: Date?

        if let publishedInterval = json["published"].double {
            publishedAt = Date(timeIntervalSince1970: publishedInterval)
        }

        let videoID = json["videoId"].stringValue

        if let index = json["indexId"].string {
            indexID = index
            id = videoID + index
        } else {
            indexID = nil
            id = videoID
        }

        return Video(
            id: id,
            videoID: videoID,
            title: json["title"].stringValue,
            author: json["author"].stringValue,
            length: json["lengthSeconds"].doubleValue,
            published: json["publishedText"].stringValue,
            views: json["viewCount"].intValue,
            description: json["description"].stringValue,
            genre: json["genre"].stringValue,
            channel: extractChannel(from: json),
            thumbnails: extractThumbnails(from: json),
            indexID: indexID,
            live: json["liveNow"].boolValue,
            upcoming: json["isUpcoming"].boolValue,
            publishedAt: publishedAt,
            likes: json["likeCount"].int,
            dislikes: json["dislikeCount"].int,
            keywords: json["keywords"].arrayValue.map { $0.stringValue },
            streams: extractFormatStreams(from: json["formatStreams"].arrayValue) +
                extractAdaptiveFormats(from: json["adaptiveFormats"].arrayValue)
        )
    }

    static func extractChannel(from json: JSON) -> Channel {
        let thumbnailURL = "https:\(json["authorThumbnails"].arrayValue.first?.dictionaryValue["url"]?.stringValue ?? "")"

        return Channel(
            id: json["authorId"].stringValue,
            name: json["author"].stringValue,
            thumbnailURL: URL(string: thumbnailURL),
            subscriptionsCount: json["subCount"].int,
            subscriptionsText: json["subCountText"].string,
            videos: json.dictionaryValue["latestVideos"]?.arrayValue.map(InvidiousAPI.extractVideo) ?? []
        )
    }

    static func extractChannelPlaylist(from json: JSON) -> ChannelPlaylist {
        let details = json.dictionaryValue
        return ChannelPlaylist(
            id: details["playlistId"]!.stringValue,
            title: details["title"]!.stringValue,
            thumbnailURL: details["playlistThumbnail"]?.url,
            channel: extractChannel(from: json),
            videos: details["videos"]?.arrayValue.compactMap(InvidiousAPI.extractVideo) ?? []
        )
    }

    private static func extractThumbnails(from details: JSON) -> [Thumbnail] {
        details["videoThumbnails"].arrayValue.map { json in
            Thumbnail(url: json["url"].url!, quality: .init(rawValue: json["quality"].string!)!)
        }
    }

    private static func extractFormatStreams(from streams: [JSON]) -> [Stream] {
        streams.map {
            SingleAssetStream(
                avAsset: AVURLAsset(url: $0["url"].url!),
                resolution: Stream.Resolution.from(resolution: $0["resolution"].stringValue),
                kind: .stream,
                encoding: $0["encoding"].stringValue
            )
        }
    }

    private static func extractAdaptiveFormats(from streams: [JSON]) -> [Stream] {
        let audioAssetURL = streams.first { $0["type"].stringValue.starts(with: "audio/mp4") }
        guard audioAssetURL != nil else {
            return []
        }

        let videoAssetsURLs = streams.filter { $0["type"].stringValue.starts(with: "video/mp4") && $0["encoding"].stringValue == "h264" }

        return videoAssetsURLs.map {
            Stream(
                audioAsset: AVURLAsset(url: audioAssetURL!["url"].url!),
                videoAsset: AVURLAsset(url: $0["url"].url!),
                resolution: Stream.Resolution.from(resolution: $0["resolution"].stringValue),
                kind: .adaptive,
                encoding: $0["encoding"].stringValue
            )
        }
    }
}
