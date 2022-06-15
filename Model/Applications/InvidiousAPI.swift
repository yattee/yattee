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
        signedIn = false

        validInstance = account.anonymous

        configure()

        if !account.anonymous {
            validate()
        }
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
            if !self.account.username.isEmpty {
                $0.headers["Cookie"] = self.cookieHeader
            }
            $0.pipeline[.parsing].add(SwiftyJSONTransformer, contentTypes: ["*/json"])
        }

        configure("**", requestMethods: [.post]) {
            $0.pipeline[.parsing].removeTransformers()
        }

        configureTransformer(pathPattern("popular"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Video] in
            content.json.arrayValue.map(self.extractVideo)
        }

        configureTransformer(pathPattern("trending"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Video] in
            content.json.arrayValue.map(self.extractVideo)
        }

        configureTransformer(pathPattern("search"), requestMethods: [.get]) { (content: Entity<JSON>) -> SearchPage in
            let results = content.json.arrayValue.compactMap { json -> ContentItem? in
                let type = json.dictionaryValue["type"]?.stringValue

                if type == "channel" {
                    return ContentItem(channel: self.extractChannel(from: json))
                } else if type == "playlist" {
                    return ContentItem(playlist: self.extractChannelPlaylist(from: json))
                } else if type == "video" {
                    return ContentItem(video: self.extractVideo(from: json))
                }

                return nil
            }

            return SearchPage(results: results, last: results.isEmpty)
        }

        configureTransformer(pathPattern("search/suggestions"), requestMethods: [.get]) { (content: Entity<JSON>) -> [String] in
            if let suggestions = content.json.dictionaryValue["suggestions"] {
                return suggestions.arrayValue.map(String.init)
            }

            return []
        }

        configureTransformer(pathPattern("auth/playlists"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Playlist] in
            content.json.arrayValue.map(self.extractPlaylist)
        }

        configureTransformer(pathPattern("auth/playlists/*"), requestMethods: [.get]) { (content: Entity<JSON>) -> Playlist in
            self.extractPlaylist(from: content.json)
        }

        configureTransformer(pathPattern("auth/playlists"), requestMethods: [.post, .patch]) { (content: Entity<Data>) -> Playlist in
            // hacky, to verify if possible to get it in easier way
            Playlist(JSON(parseJSON: String(data: content.content, encoding: .utf8)!))
        }

        configureTransformer(pathPattern("auth/feed"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Video] in
            if let feedVideos = content.json.dictionaryValue["videos"] {
                return feedVideos.arrayValue.map(self.extractVideo)
            }

            return []
        }

        configureTransformer(pathPattern("auth/subscriptions"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Channel] in
            content.json.arrayValue.map(self.extractChannel)
        }

        configureTransformer(pathPattern("channels/*"), requestMethods: [.get]) { (content: Entity<JSON>) -> Channel in
            self.extractChannel(from: content.json)
        }

        configureTransformer(pathPattern("channels/*/latest"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Video] in
            content.json.arrayValue.map(self.extractVideo)
        }

        configureTransformer(pathPattern("playlists/*"), requestMethods: [.get]) { (content: Entity<JSON>) -> ChannelPlaylist in
            self.extractChannelPlaylist(from: content.json)
        }

        configureTransformer(pathPattern("videos/*"), requestMethods: [.get]) { (content: Entity<JSON>) -> Video in
            self.extractVideo(from: content.json)
        }
    }

    private func pathPattern(_ path: String) -> String {
        "**\(Self.basePath)/\(path)"
    }

    private func basePathAppending(_ path: String) -> String {
        "\(Self.basePath)/\(path)"
    }

    private var cookieHeader: String {
        "SID=\(account.username)"
    }

    var popular: Resource? {
        resource(baseURL: account.url, path: "\(Self.basePath)/popular")
    }

    func trending(country: Country, category: TrendingCategory?) -> Resource {
        resource(baseURL: account.url, path: "\(Self.basePath)/trending")
            .withParam("type", category?.name)
            .withParam("region", country.rawValue)
    }

    var home: Resource? {
        resource(baseURL: account.url, path: "/feed/subscriptions")
    }

    var feed: Resource? {
        resource(baseURL: account.url, path: "\(Self.basePath)/auth/feed")
    }

    var subscriptions: Resource? {
        resource(baseURL: account.url, path: basePathAppending("auth/subscriptions"))
    }

    func subscribe(_ channelID: String, onCompletion: @escaping () -> Void = {}) {
        resource(baseURL: account.url, path: basePathAppending("auth/subscriptions"))
            .child(channelID)
            .request(.post)
            .onCompletion { _ in onCompletion() }
    }

    func unsubscribe(_ channelID: String, onCompletion: @escaping () -> Void) {
        resource(baseURL: account.url, path: basePathAppending("auth/subscriptions"))
            .child(channelID)
            .request(.delete)
            .onCompletion { _ in onCompletion() }
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
        if account.isNil || account.anonymous {
            return nil
        }

        return resource(baseURL: account.url, path: basePathAppending("auth/playlists"))
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

    func addVideoToPlaylist(
        _ videoID: String,
        _ playlistID: String,
        onFailure: @escaping (RequestError) -> Void = { _ in },
        onSuccess: @escaping () -> Void = {}
    ) {
        let resource = playlistVideos(playlistID)
        let body = ["videoId": videoID]

        resource?
            .request(.post, json: body)
            .onSuccess { _ in onSuccess() }
            .onFailure(onFailure)
    }

    func removeVideoFromPlaylist(
        _ index: String,
        _ playlistID: String,
        onFailure: @escaping (RequestError) -> Void,
        onSuccess: @escaping () -> Void
    ) {
        let resource = playlistVideo(playlistID, index)

        resource?
            .request(.delete)
            .onSuccess { _ in onSuccess() }
            .onFailure(onFailure)
    }

    func playlistForm(
        _ name: String,
        _ visibility: String,
        playlist: Playlist?,
        onFailure: @escaping (RequestError) -> Void,
        onSuccess: @escaping (Playlist?) -> Void
    ) {
        let body = ["title": name, "privacy": visibility]
        let resource = !playlist.isNil ? self.playlist(playlist!.id) : playlists

        resource?
            .request(!playlist.isNil ? .patch : .post, json: body)
            .onSuccess { response in
                if let modifiedPlaylist: Playlist = response.typedContent() {
                    onSuccess(modifiedPlaylist)
                }
            }
            .onFailure(onFailure)
    }

    func deletePlaylist(
        _ playlist: Playlist,
        onFailure: @escaping (RequestError) -> Void,
        onSuccess: @escaping () -> Void
    ) {
        self.playlist(playlist.id)?
            .request(.delete)
            .onSuccess { _ in onSuccess() }
            .onFailure(onFailure)
    }

    func channelPlaylist(_ id: String) -> Resource? {
        resource(baseURL: account.url, path: basePathAppending("playlists/\(id)"))
    }

    func search(_ query: SearchQuery, page: String?) -> Resource {
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

        if let page = page {
            resource = resource.withParam("page", page)
        }

        return resource
    }

    func searchSuggestions(query: String) -> Resource {
        resource(baseURL: account.url, path: basePathAppending("search/suggestions"))
            .withParam("q", query.lowercased())
    }

    func comments(_: Video.ID, page _: String?) -> Resource? { nil }

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
        guard let instanceURLComponents = URLComponents(string: instance.apiURL),
              var urlComponents = URLComponents(url: asset.url, resolvingAgainstBaseURL: false) else { return nil }

        urlComponents.scheme = instanceURLComponents.scheme
        urlComponents.host = instanceURLComponents.host

        guard let url = urlComponents.url else {
            return nil
        }

        return AVURLAsset(url: url)
    }

    func extractVideo(from json: JSON) -> Video {
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
            streams: extractStreams(from: json),
            related: extractRelated(from: json)
        )
    }

    func extractChannel(from json: JSON) -> Channel {
        var thumbnailURL = json["authorThumbnails"].arrayValue.last?.dictionaryValue["url"]?.stringValue ?? ""

        // append protocol to unproxied thumbnail URL if it's missing
        if thumbnailURL.count > 2,
           String(thumbnailURL[..<thumbnailURL.index(thumbnailURL.startIndex, offsetBy: 2)]) == "//",
           let accountUrlComponents = URLComponents(string: account.url)
        {
            thumbnailURL = "\(accountUrlComponents.scheme ?? "https"):\(thumbnailURL)"
        }

        return Channel(
            id: json["authorId"].stringValue,
            name: json["author"].stringValue,
            thumbnailURL: URL(string: thumbnailURL),
            subscriptionsCount: json["subCount"].int,
            subscriptionsText: json["subCountText"].string,
            videos: json.dictionaryValue["latestVideos"]?.arrayValue.map(extractVideo) ?? []
        )
    }

    func extractChannelPlaylist(from json: JSON) -> ChannelPlaylist {
        let details = json.dictionaryValue
        return ChannelPlaylist(
            id: details["playlistId"]!.stringValue,
            title: details["title"]!.stringValue,
            thumbnailURL: details["playlistThumbnail"]?.url,
            channel: extractChannel(from: json),
            videos: details["videos"]?.arrayValue.compactMap(extractVideo) ?? []
        )
    }

    private func extractThumbnails(from details: JSON) -> [Thumbnail] {
        details["videoThumbnails"].arrayValue.compactMap { json in
            guard let url = json["url"].url,
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let quality = json["quality"].string,
                  let accountUrlComponents = URLComponents(string: account.url)
            else {
                return nil
            }

            // some of instances are not configured properly and return thumbnails links
            // with incorrect scheme
            components.scheme = accountUrlComponents.scheme

            guard let thumbnailUrl = components.url else {
                return nil
            }

            return Thumbnail(url: thumbnailUrl, quality: .init(rawValue: quality)!)
        }
    }

    private func extractStreams(from json: JSON) -> [Stream] {
        extractFormatStreams(from: json["formatStreams"].arrayValue) +
            extractAdaptiveFormats(from: json["adaptiveFormats"].arrayValue)
    }

    private func extractFormatStreams(from streams: [JSON]) -> [Stream] {
        streams.map {
            SingleAssetStream(
                avAsset: AVURLAsset(url: $0["url"].url!),
                resolution: Stream.Resolution.from(resolution: $0["resolution"].stringValue),
                kind: .stream,
                encoding: $0["encoding"].stringValue
            )
        }
    }

    private func extractAdaptiveFormats(from streams: [JSON]) -> [Stream] {
        let audioAssetURL = streams.first { $0["type"].stringValue.starts(with: "audio/mp4") }
        guard audioAssetURL != nil else {
            return []
        }

        let videoAssetsURLs = streams.filter { $0["type"].stringValue.starts(with: "video/") }

        return videoAssetsURLs.map {
            Stream(
                audioAsset: AVURLAsset(url: audioAssetURL!["url"].url!),
                videoAsset: AVURLAsset(url: $0["url"].url!),
                resolution: Stream.Resolution.from(resolution: $0["resolution"].stringValue),
                kind: .adaptive,
                encoding: $0["encoding"].stringValue,
                videoFormat: $0["type"].stringValue
            )
        }
    }

    private func extractRelated(from content: JSON) -> [Video] {
        content
            .dictionaryValue["recommendedVideos"]?
            .arrayValue
            .compactMap(extractVideo(from:)) ?? []
    }

    private func extractPlaylist(from content: JSON) -> Playlist {
        .init(
            id: content["playlistId"].stringValue,
            title: content["title"].stringValue,
            visibility: content["isListed"].boolValue ? .public : .private,
            updated: content["updated"].doubleValue,
            videos: content["videos"].arrayValue.map { extractVideo(from: $0) }
        )
    }
}
