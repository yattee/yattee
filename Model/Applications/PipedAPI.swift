import Alamofire
import AVFoundation
import Foundation
import Siesta
import SwiftyJSON

final class PipedAPI: Service, ObservableObject, VideosAPI {
    static var disallowedVideoCodecs = ["av01"]
    static var authorizedEndpoints = ["subscriptions", "subscribe", "unsubscribe", "user/playlists"]
    static var contentItemsKeys = ["items", "content", "relatedStreams"]

    @Published var account: Account!

    static func withAnonymousAccountForInstanceURL(_ url: URL) -> PipedAPI {
        .init(account: Instance(app: .piped, apiURLString: url.absoluteString).anonymousAccount)
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

        configureTransformer(pathPattern("channel/*")) { (content: Entity<JSON>) -> ChannelPage in
            let nextPage = content.json.dictionaryValue["nextpage"]?.string
            let channel = self.extractChannel(from: content.json)
            return ChannelPage(
                results: self.extractContentItems(from: self.contentItemsDictionary(from: content.json)),
                channel: channel,
                nextPage: nextPage,
                last: nextPage.isNil
            )
        }

        configureTransformer(pathPattern("/nextpage/channel/*")) { (content: Entity<JSON>) -> ChannelPage in
            let nextPage = content.json.dictionaryValue["nextpage"]?.string
            return ChannelPage(
                results: self.extractContentItems(from: self.contentItemsDictionary(from: content.json)),
                channel: self.extractChannel(from: content.json),
                nextPage: nextPage,
                last: nextPage.isNil
            )
        }

        configureTransformer(pathPattern("channels/tabs*")) { (content: Entity<JSON>) -> [ContentItem] in
            (content.json.dictionaryValue["content"]?.arrayValue ?? []).compactMap { self.extractContentItem(from: $0) }
        }

        configureTransformer(pathPattern("c/*")) { (content: Entity<JSON>) -> Channel? in
            self.extractChannel(from: content.json)
        }

        configureTransformer(pathPattern("user/*")) { (content: Entity<JSON>) -> Channel? in
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

        configureTransformer(pathPattern("comments/*")) { (content: Entity<JSON>?) -> CommentsPage in
            guard let details = content?.json.dictionaryValue else {
                return CommentsPage(comments: [], nextPage: nil, disabled: true)
            }

            let comments = details["comments"]?.arrayValue.compactMap { self.extractComment(from: $0) } ?? []
            let nextPage = details["nextpage"]?.string
            let disabled = details["disabled"]?.bool ?? false

            return CommentsPage(comments: comments, nextPage: nextPage, disabled: disabled)
        }

        configureTransformer(pathPattern("user/playlists")) { (content: Entity<JSON>) -> [Playlist] in
            content.json.arrayValue.compactMap { self.extractUserPlaylist(from: $0) }
        }

        if account.token.isNil || account.token!.isEmpty {
            updateToken()
        } else {
            FeedModel.shared.onAccountChange()
            SubscribedChannelsModel.shared.onAccountChange()
            PlaylistsModel.shared.onAccountChange()
        }
    }

    func needsAuthorization(_ url: URL) -> Bool {
        Self.authorizedEndpoints.contains { url.absoluteString.contains($0) }
    }

    func updateToken() {
        let (username, password) = AccountsModel.getCredentials(account)

        guard !account.anonymous,
              let username,
              let password
        else {
            return
        }

        AF.request(
            login.url,
            method: .post,
            parameters: ["username": username, "password": password],
            encoding: JSONEncoding.default
        )
        .responseDecodable(of: JSON.self) { [weak self] response in
            guard let self else {
                return
            }

            switch response.result {
            case let .success(value):
                let json = JSON(value)
                let token = json.dictionaryValue["token"]?.string ?? ""
                if let error = json.dictionaryValue["error"]?.string {
                    NavigationModel.shared.presentAlert(
                        title: "Account Error",
                        message: error
                    )
                } else if !token.isEmpty {
                    AccountsModel.setToken(self.account, token)
                    self.objectWillChange.send()
                } else {
                    NavigationModel.shared.presentAlert(
                        title: "Account Error",
                        message: "Could not update your token."
                    )
                }

                self.configure()

            case let .failure(error):
                NavigationModel.shared.presentAlert(
                    title: "Account Error",
                    message: error.localizedDescription
                )
            }
        }
    }

    var login: Resource {
        resource(baseURL: account.url, path: "login")
    }

    func channel(_ id: String, contentType: Channel.ContentType, data: String?, page: String?) -> Resource {
        let path = page.isNil ? "channel" : "nextpage/channel"

        var channel: Siesta.Resource

        if contentType == .videos || data.isNil {
            channel = resource(baseURL: account.url, path: "\(path)/\(id)")
        } else {
            channel = resource(baseURL: account.url, path: "channels/tabs")
                .withParam("data", data)
        }

        if let page, !page.isEmpty {
            channel = channel.withParam("nextpage", page)
        }

        return channel
    }

    func channelByName(_ name: String) -> Resource? {
        resource(baseURL: account.url, path: "c/\(name)")
    }

    func channelByUsername(_ username: String) -> Resource? {
        resource(baseURL: account.url, path: "user/\(username)")
    }

    func channelVideos(_ id: String) -> Resource {
        channel(id, contentType: .videos)
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
        guard let account else {
            return false
        }

        return !account.anonymous && !(account.token?.isEmpty ?? true)
    }

    var subscriptions: Resource? {
        resource(baseURL: account.instance.apiURL, path: "subscriptions")
    }

    func feed(_: Int?) -> Resource? {
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

        let tabs = attributes["tabs"]?.arrayValue.compactMap { tab in
            let name = tab["name"].string
            let data = tab["data"].string
            if let name, let data, let type = Channel.ContentType(rawValue: name) {
                return Channel.Tab(contentType: type, data: data)
            }

            return nil
        } ?? [Channel.Tab]()

        return Channel(
            app: .piped,
            id: id,
            name: name,
            bannerURL: attributes["bannerUrl"]?.url,
            thumbnailURL: thumbnailURL,
            subscriptionsCount: subscriptionsCount,
            verified: attributes["verified"]?.bool,
            videos: videos,
            tabs: tabs
        )
    }

    func extractChannelPlaylist(from json: JSON) -> ChannelPlaylist? {
        let details = json.dictionaryValue
        let id = details["url"]?.stringValue.components(separatedBy: "?list=").last
        let thumbnailURL = details["thumbnail"]?.url ?? details["thumbnailUrl"]?.url
        var videos = [Video]()
        if let relatedStreams = details["relatedStreams"] {
            videos = extractVideos(from: relatedStreams)
        }
        return ChannelPlaylist(
            id: id ?? UUID().uuidString,
            title: details["name"]?.string ?? "",
            thumbnailURL: thumbnailURL,
            channel: extractChannel(from: json),
            videos: videos,
            videosCount: details["videos"]?.int
        )
    }

    static func nonProxiedAsset(asset: AVURLAsset, completion: @escaping (AVURLAsset?) -> Void) {
        guard var urlComponents = URLComponents(url: asset.url, resolvingAgainstBaseURL: false) else {
            completion(asset)
            return
        }

        guard let hostItem = urlComponents.queryItems?.first(where: { $0.name == "host" }),
              let hostValue = hostItem.value
        else {
            completion(asset)
            return
        }

        urlComponents.host = hostValue

        guard let newUrl = urlComponents.url else {
            completion(asset)
            return
        }

        completion(AVURLAsset(url: newUrl))
    }

    // Overload used for hlsURLS
    static func nonProxiedAsset(url: URL, completion: @escaping (AVURLAsset?) -> Void) {
        let asset = AVURLAsset(url: url)
        nonProxiedAsset(asset: asset, completion: completion)
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
        var publishedAt: Date?

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        if published.isNil,
           let date = details["uploadDate"]?.string,
           let formattedDate = dateFormatter.date(from: date)
        {
            publishedAt = formattedDate
        } else {
            published = (details["uploadedDate"] ?? details["uploadDate"])?.string ?? ""
        }

        let live = details["livestream"]?.bool ?? (details["duration"]?.int == -1)

        let description = extractDescription(from: content) ?? ""

        var chapters = extractChapters(from: content)
        if chapters.isEmpty, !description.isEmpty {
            chapters = extractChapters(from: description)
        }

        let length = details["duration"]?.double ?? 0

        return Video(
            instanceID: account.instanceID,
            app: .piped,
            instanceURL: account.instance.apiURL,
            videoID: extractID(from: content),
            title: details["title"]?.string ?? "",
            author: author,
            length: length,
            published: published ?? "",
            views: details["views"]?.int ?? 0,
            description: description,
            channel: Channel(app: .piped, id: channelId, name: author, thumbnailURL: authorThumbnailURL, subscriptionsCount: subscriptionsCount),
            thumbnails: thumbnails,
            live: live,
            short: details["isShort"]?.bool ?? (length <= Video.shortLength),
            publishedAt: publishedAt,
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

        return URL(
            string: thumbnailURL
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
        guard let description = content.dictionaryValue["description"]?.string else { return nil }

        return replaceHTML(description)
    }

    private func replaceHTML(_ string: String) -> String {
        var string = string.replacingOccurrences(
            of: "<br/>|<br />|<br>",
            with: "\n",
            options: .regularExpression,
            range: nil
        )

        let linkRegex = #"(<a\s+(?:[^>]*?\s+)?href=\"[^"]*\">[^<]*<\/a>)"#
        let hrefRegex = #"href=\"([^"]*)\">"#
        guard let hrefRegex = try? NSRegularExpression(pattern: hrefRegex) else { return string }
        string = string.replacingMatches(regex: linkRegex) { matchingGroup in
            let results = hrefRegex.matches(in: matchingGroup, range: NSRange(matchingGroup.startIndex..., in: matchingGroup))

            if let result = results.first {
                if let swiftRange = Range(result.range(at: 1), in: matchingGroup) {
                    return String(matchingGroup[swiftRange])
                }
            }

            return matchingGroup
        }

        string = string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(
                of: "<[^>]+>",
                with: "",
                options: .regularExpression,
                range: nil
            )

        return string
    }

    private func extractVideos(from content: JSON) -> [Video] {
        content.arrayValue.compactMap(extractVideo(from:))
    }

    private func extractStreams(from content: JSON) -> [Stream] {
        var streams = [Stream]()

        if let hlsURL = content.dictionaryValue["hls"]?.url {
            streams.append(Stream(instance: account.instance, hlsURL: hlsURL))
        }

        let audioStreams = content
            .dictionaryValue["audioStreams"]?
            .arrayValue
            .filter { $0.dictionaryValue["format"]?.string == "M4A" }
            .filter { stream in
                let type = stream.dictionaryValue["audioTrackType"]?.string
                return type == nil || type == "ORIGINAL"
            }
            .sorted {
                $0.dictionaryValue["bitrate"]?.int ?? 0 >
                    $1.dictionaryValue["bitrate"]?.int ?? 0
            } ?? []

        guard let audioStream = audioStreams.first else {
            return streams
        }

        let videoStreams = content.dictionaryValue["videoStreams"]?.arrayValue ?? []

        for videoStream in videoStreams {
            let videoCodec = videoStream.dictionaryValue["codec"]?.string ?? ""
            if Self.disallowedVideoCodecs.contains(where: videoCodec.contains) {
                continue
            }

            guard let audioAssetUrl = audioStream.dictionaryValue["url"]?.url,
                  let videoAssetUrl = videoStream.dictionaryValue["url"]?.url
            else {
                continue
            }

            let audioAsset = AVURLAsset(url: audioAssetUrl)
            let videoAsset = AVURLAsset(url: videoAssetUrl)

            let videoOnly = videoStream.dictionaryValue["videoOnly"]?.bool ?? true
            let quality = videoStream.dictionaryValue["quality"]?.string ?? "unknown"
            let qualityComponents = quality.components(separatedBy: "p")
            let fps = qualityComponents.count > 1 ? Int(qualityComponents[1]) : 30
            let resolution = Stream.Resolution.from(resolution: quality, fps: fps)
            let videoFormat = videoStream.dictionaryValue["format"]?.string
            let bitrate = videoStream.dictionaryValue["bitrate"]?.int
            var requestRange: String?

            if let initStart = videoStream.dictionaryValue["initStart"]?.int,
               let initEnd = videoStream.dictionaryValue["initEnd"]?.int
            {
                requestRange = "\(initStart)-\(initEnd)"
            } else if let indexStart = videoStream.dictionaryValue["indexStart"]?.int,
                      let indexEnd = videoStream.dictionaryValue["indexEnd"]?.int
            {
                requestRange = "\(indexStart)-\(indexEnd)"
            } else {
                requestRange = nil
            }

            if videoOnly {
                streams.append(
                    Stream(
                        instance: account.instance,
                        audioAsset: audioAsset,
                        videoAsset: videoAsset,
                        resolution: resolution,
                        kind: .adaptive,
                        videoFormat: videoFormat,
                        bitrate: bitrate,
                        requestRange: requestRange
                    )
                )
            } else {
                streams.append(
                    SingleAssetStream(
                        instance: account.instance,
                        avAsset: videoAsset,
                        resolution: resolution,
                        kind: .stream
                    )
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

        let commentText = extractCommentText(from: details["commentText"]?.stringValue)
        let commentId = details["commentId"]?.string ?? UUID().uuidString

        // Sanity checks: return nil if required data is missing
        if commentText.isEmpty || commentId.isEmpty || author.isEmpty {
            return nil
        }

        return Comment(
            id: commentId,
            author: author,
            authorAvatarURL: details["thumbnail"]?.string ?? "",
            time: details["commentedTime"]?.string ?? "",
            pinned: details["pinned"]?.bool ?? false,
            hearted: details["hearted"]?.bool ?? false,
            likeCount: details["likeCount"]?.int ?? 0,
            text: commentText,
            repliesPage: details["repliesPage"]?.string,
            channel: Channel(app: .piped, id: channelId, name: author)
        )
    }

    private func extractCommentText(from string: String?) -> String {
        guard let string, !string.isEmpty else { return "" }

        return replaceHTML(string)
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

    private func contentItemsDictionary(from content: JSON) -> JSON {
        if let key = Self.contentItemsKeys.first(where: { content.dictionaryValue.keys.contains($0) }),
           let items = content.dictionaryValue[key]
        {
            return items
        }

        return .null
    }
}
