import AVFoundation
import Foundation
import Siesta
import SwiftyJSON

final class PipedAPI: Service, ObservableObject, VideosAPI {
    static var disallowedVideoCodecs = ["av01"]
    static var authorizedEndpoints = ["subscriptions", "subscribe", "unsubscribe", "user/playlists"]

    @Published var account: Account!

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
            self.extractChannel(from: content.json)
        }

        configureTransformer(pathPattern("playlists/*")) { (content: Entity<JSON>) -> ChannelPlaylist? in
            self.extractChannelPlaylist(from: content.json)
        }

        configureTransformer(pathPattern("user/playlists/create")) { (_: Entity<JSON>) in }
        configureTransformer(pathPattern("user/playlists/delete")) { (_: Entity<JSON>) in }
        configureTransformer(pathPattern("user/playlists/add")) { (_: Entity<JSON>) in }
        configureTransformer(pathPattern("user/playlists/remove")) { (_: Entity<JSON>) in }

        configureTransformer(pathPattern("streams/*")) { (content: Entity<JSON>) -> Video? in
            self.extractVideo(from: content.json)
        }

        configureTransformer(pathPattern("trending")) { (content: Entity<JSON>) -> [Video] in
            self.extractVideos(from: content.json)
        }

        configureTransformer(pathPattern("search")) { (content: Entity<JSON>) -> SearchPage in
            let nextPage = content.json.dictionaryValue["nextpage"]?.string
            return SearchPage(
                results: self.extractContentItems(from: content.json.dictionaryValue["items"]!),
                nextPage: nextPage,
                last: nextPage == "null"
            )
        }

        configureTransformer(pathPattern("suggestions")) { (content: Entity<JSON>) -> [String] in
            content.json.arrayValue.map(String.init)
        }

        configureTransformer(pathPattern("subscriptions")) { (content: Entity<JSON>) -> [Channel] in
            content.json.arrayValue.compactMap { self.extractChannel(from: $0) }
        }

        configureTransformer(pathPattern("feed")) { (content: Entity<JSON>) -> [Video] in
            content.json.arrayValue.compactMap { self.extractVideo(from: $0) }
        }

        configureTransformer(pathPattern("comments/*")) { (content: Entity<JSON>) -> CommentsPage in
            let details = content.json.dictionaryValue
            let comments = details["comments"]?.arrayValue.compactMap { self.extractComment(from: $0) } ?? []
            let nextPage = details["nextpage"]?.string
            let disabled = details["disabled"]?.bool ?? false

            return CommentsPage(comments: comments, nextPage: nextPage, disabled: disabled)
        }

        configureTransformer(pathPattern("user/playlists")) { (content: Entity<JSON>) -> [Playlist] in
            content.json.arrayValue.compactMap { self.extractUserPlaylist(from: $0) }
        }

        if account.token.isNil {
            updateToken()
        }
    }

    func needsAuthorization(_ url: URL) -> Bool {
        Self.authorizedEndpoints.contains { url.absoluteString.contains($0) }
    }

    func updateToken() {
        guard !account.anonymous else {
            return
        }

        account.token = nil

        login.request(
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

    func search(_ query: SearchQuery, page: String?) -> Resource {
        let path = page.isNil ? "search" : "nextpage/search"

        let resource = resource(baseURL: account.instance.apiURL, path: path)
            .withParam("q", query.query)
            .withParam("filter", "all")

        if page.isNil {
            return resource
        }

        return resource.withParam("nextpage", page)
    }

    func searchSuggestions(query: String) -> Resource {
        resource(baseURL: account.instance.apiURL, path: "suggestions")
            .withParam("query", query.lowercased())
    }

    func video(_ id: Video.ID) -> Resource {
        resource(baseURL: account.instance.apiURL, path: "streams/\(id)")
    }

    var signedIn: Bool {
        guard let account = account else {
            return false
        }

        return !account.anonymous && !(account.token?.isEmpty ?? true)
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
    var playlists: Resource? {
        resource(baseURL: account.instance.apiURL, path: "user/playlists")
    }

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

    func playlist(_ id: String) -> Resource? {
        channelPlaylist(id)
    }

    func playlistVideo(_: String, _: String) -> Resource? { nil }
    func playlistVideos(_: String) -> Resource? { nil }

    func addVideoToPlaylist(
        _ videoID: String,
        _ playlistID: String,
        onFailure: @escaping (RequestError) -> Void = { _ in },
        onSuccess: @escaping () -> Void = {}
    ) {
        let resource = resource(baseURL: account.instance.apiURL, path: "user/playlists/add")
        let body = ["videoId": videoID, "playlistId": playlistID]

        resource
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
        let resource = resource(baseURL: account.instance.apiURL, path: "user/playlists/remove")
        let body: [String: Any] = ["index": Int(index)!, "playlistId": playlistID]

        resource
            .request(.post, json: body)
            .onSuccess { _ in onSuccess() }
            .onFailure(onFailure)
    }

    func playlistForm(
        _ name: String,
        _: String,
        playlist: Playlist?,
        onFailure: @escaping (RequestError) -> Void,
        onSuccess: @escaping (Playlist?) -> Void
    ) {
        let body = ["name": name]
        let resource = playlist.isNil ? resource(baseURL: account.instance.apiURL, path: "user/playlists/create") : nil

        resource?
            .request(.post, json: body)
            .onSuccess { response in
                if let modifiedPlaylist: Playlist = response.typedContent() {
                    onSuccess(modifiedPlaylist)
                } else {
                    onSuccess(nil)
                }
            }
            .onFailure(onFailure)
    }

    func deletePlaylist(
        _ playlist: Playlist,
        onFailure: @escaping (RequestError) -> Void,
        onSuccess: @escaping () -> Void
    ) {
        let resource = resource(baseURL: account.instance.apiURL, path: "user/playlists/delete")
        let body = ["playlistId": playlist.id]

        resource
            .request(.post, json: body)
            .onSuccess { _ in onSuccess() }
            .onFailure(onFailure)
    }

    func comments(_ id: Video.ID, page: String?) -> Resource? {
        let path = page.isNil ? "comments/\(id)" : "nextpage/comments/\(id)"
        let resource = resource(baseURL: account.url, path: path)

        if page.isNil {
            return resource
        }

        return resource.withParam("nextpage", page)
    }

    private func pathPattern(_ path: String) -> String {
        "**\(path)"
    }

    private func extractContentItem(from content: JSON) -> ContentItem? {
        let details = content.dictionaryValue

        let contentType: ContentItem.ContentType

        if let url = details["url"]?.string {
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
            if let video = extractVideo(from: content) {
                return ContentItem(video: video)
            }

        case .playlist:
            if let playlist = extractChannelPlaylist(from: content) {
                return ContentItem(playlist: playlist)
            }

        case .channel:
            if let channel = extractChannel(from: content) {
                return ContentItem(channel: channel)
            }
        default:
            return nil
        }

        return nil
    }

    private func extractContentItems(from content: JSON) -> [ContentItem] {
        content.arrayValue.compactMap { extractContentItem(from: $0) }
    }

    private func extractChannel(from content: JSON) -> Channel? {
        let attributes = content.dictionaryValue
        guard let id = attributes["id"]?.string ??
            (attributes["url"] ?? attributes["uploaderUrl"])?.string?.components(separatedBy: "/").last
        else {
            return nil
        }

        let subscriptionsCount = attributes["subscriberCount"]?.int ?? attributes["subscribers"]?.int

        var videos = [Video]()
        if let relatedStreams = attributes["relatedStreams"] {
            videos = extractVideos(from: relatedStreams)
        }

        let name = attributes["name"]?.string ??
            attributes["uploaderName"]?.string ??
            attributes["uploader"]?.string ?? ""

        let thumbnailURL = attributes["avatarUrl"]?.url ??
            attributes["uploaderAvatar"]?.url ??
            attributes["avatar"]?.url ??
            attributes["thumbnail"]?.url

        return Channel(
            id: id,
            name: name,
            thumbnailURL: thumbnailURL,
            subscriptionsCount: subscriptionsCount,
            videos: videos
        )
    }

    func extractChannelPlaylist(from json: JSON) -> ChannelPlaylist? {
        let details = json.dictionaryValue
        let id = details["url"]?.string?.components(separatedBy: "?list=").last ?? UUID().uuidString
        let thumbnailURL = details["thumbnail"]?.url ?? details["thumbnailUrl"]?.url
        var videos = [Video]()
        if let relatedStreams = details["relatedStreams"] {
            videos = extractVideos(from: relatedStreams)
        }
        return ChannelPlaylist(
            id: id,
            title: details["name"]?.string ?? "",
            thumbnailURL: thumbnailURL,
            channel: extractChannel(from: json),
            videos: videos,
            videosCount: details["videos"]?.int
        )
    }

    private func extractVideo(from content: JSON) -> Video? {
        let details = content.dictionaryValue

        if let url = details["url"]?.string {
            guard url.contains("/watch") else {
                return nil
            }
        }

        let channelId = details["uploaderUrl"]?.string?.components(separatedBy: "/").last ?? "unknown"

        let thumbnails: [Thumbnail] = Thumbnail.Quality.allCases.compactMap {
            if let url = buildThumbnailURL(from: content, quality: $0) {
                return Thumbnail(url: url, quality: $0)
            }

            return nil
        }

        let author = details["uploaderName"]?.string ?? details["uploader"]?.string ?? ""
        let authorThumbnailURL = details["avatarUrl"]?.url ?? details["uploaderAvatar"]?.url ?? details["avatar"]?.url
        let subscriptionsCount = details["uploaderSubscriberCount"]?.int

        let uploaded = details["uploaded"]?.double
        var published = (uploaded.isNil || uploaded == -1) ? nil : (uploaded! / 1000).formattedAsRelativeTime()
        if published.isNil {
            published = (details["uploadedDate"] ?? details["uploadDate"])?.string ?? ""
        }

        let live = details["livestream"]?.bool ?? (details["duration"]?.int == -1)

        let description = extractDescription(from: content) ?? ""

        var chapters = extractChapters(from: content)
        if chapters.isEmpty, !description.isEmpty {
            chapters = extractChapters(from: description)
        }

        return Video(
            videoID: extractID(from: content),
            title: details["title"]?.string ?? "",
            author: author,
            length: details["duration"]?.double ?? 0,
            published: published ?? "",
            views: details["views"]?.int ?? 0,
            description: description,
            channel: Channel(id: channelId, name: author, thumbnailURL: authorThumbnailURL, subscriptionsCount: subscriptionsCount),
            thumbnails: thumbnails,
            live: live,
            likes: details["likes"]?.int,
            dislikes: details["dislikes"]?.int,
            streams: extractStreams(from: content),
            related: extractRelated(from: content),
            chapters: extractChapters(from: content)
        )
    }

    private func extractID(from content: JSON) -> Video.ID {
        content.dictionaryValue["url"]?.string?.components(separatedBy: "?v=").last ??
            extractThumbnailURL(from: content)?.relativeString.components(separatedBy: "/")[4] ?? ""
    }

    private func extractThumbnailURL(from content: JSON) -> URL? {
        content.dictionaryValue["thumbnail"]?.url ?? content.dictionaryValue["thumbnailUrl"]?.url
    }

    private func buildThumbnailURL(from content: JSON, quality: Thumbnail.Quality) -> URL? {
        guard let thumbnailURL = extractThumbnailURL(from: content) else {
            return nil
        }

        return URL(string: thumbnailURL
            .absoluteString
            .replacingOccurrences(of: "hqdefault", with: quality.filename)
            .replacingOccurrences(of: "maxresdefault", with: quality.filename)
        )
    }

    private func extractUserPlaylist(from json: JSON) -> Playlist? {
        let id = json["id"].string ?? ""
        let title = json["name"].string ?? ""
        let visibility = Playlist.Visibility.private

        return Playlist(id: id, title: title, visibility: visibility)
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
            streams.append(Stream(hlsURL: hlsURL))
        }

        let audioStreams = content
            .dictionaryValue["audioStreams"]?
            .arrayValue
            .filter { $0.dictionaryValue["format"]?.string == "M4A" }
            .sorted {
                $0.dictionaryValue["bitrate"]?.int ?? 0 >
                    $1.dictionaryValue["bitrate"]?.int ?? 0
            } ?? []

        guard let audioStream = audioStreams.first else {
            return streams
        }

        let videoStreams = content.dictionaryValue["videoStreams"]?.arrayValue ?? []

        videoStreams.forEach { videoStream in
            let videoCodec = videoStream.dictionaryValue["codec"]?.string ?? ""
            if Self.disallowedVideoCodecs.contains(where: videoCodec.contains) {
                return
            }

            guard let audioAssetUrl = audioStream.dictionaryValue["url"]?.url,
                  let videoAssetUrl = videoStream.dictionaryValue["url"]?.url
            else {
                return
            }

            let audioAsset = AVURLAsset(url: audioAssetUrl)
            let videoAsset = AVURLAsset(url: videoAssetUrl)

            let videoOnly = videoStream.dictionaryValue["videoOnly"]?.bool ?? true
            let quality = videoStream.dictionaryValue["quality"]?.string ?? "unknown"
            let qualityComponents = quality.components(separatedBy: "p")
            let fps = qualityComponents.count > 1 ? Int(qualityComponents[1]) : 30
            let resolution = Stream.Resolution.from(resolution: quality, fps: fps)
            let videoFormat = videoStream.dictionaryValue["format"]?.string

            if videoOnly {
                streams.append(
                    Stream(
                        audioAsset: audioAsset,
                        videoAsset: videoAsset,
                        resolution: resolution,
                        kind: .adaptive,
                        videoFormat: videoFormat
                    )
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

    private func extractComment(from content: JSON) -> Comment? {
        let details = content.dictionaryValue
        let author = details["author"]?.string ?? ""
        let commentorUrl = details["commentorUrl"]?.string
        let channelId = commentorUrl?.components(separatedBy: "/")[2] ?? ""
        return Comment(
            id: details["commentId"]?.string ?? UUID().uuidString,
            author: author,
            authorAvatarURL: details["thumbnail"]?.string ?? "",
            time: details["commentedTime"]?.string ?? "",
            pinned: details["pinned"]?.bool ?? false,
            hearted: details["hearted"]?.bool ?? false,
            likeCount: details["likeCount"]?.int ?? 0,
            text: details["commentText"]?.string ?? "",
            repliesPage: details["repliesPage"]?.string,
            channel: Channel(id: channelId, name: author)
        )
    }

    private func extractChapters(from content: JSON) -> [Chapter] {
        guard let chapters = content.dictionaryValue["chapters"]?.array else {
            return .init()
        }

        return chapters.compactMap { chapter in
            guard let title = chapter["title"].string,
                  let image = chapter["image"].url,
                  let start = chapter["start"].double
            else {
                return nil
            }

            return Chapter(title: title, image: image, start: start)
        }
    }
}
