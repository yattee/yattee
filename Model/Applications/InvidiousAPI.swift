import Alamofire
import AVKit
import Defaults
import Foundation
import Siesta
import SwiftyJSON

final class InvidiousAPI: Service, ObservableObject, VideosAPI {
    static let basePath = "/api/v1"

    @Published var account: Account!

    static func withAnonymousAccountForInstanceURL(_ url: URL) -> InvidiousAPI {
        .init(account: Instance(app: .invidious, apiURLString: url.absoluteString).anonymousAccount)
    }

    var signedIn: Bool {
        guard let account else { return false }

        return !account.anonymous && !(account.token?.isEmpty ?? true)
    }

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

        configure()
    }

    func configure() {
        invalidateConfiguration()

        configure {
            if let cookie = self.cookieHeader {
                $0.headers["Cookie"] = cookie
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
                let type = json.dictionaryValue["type"]?.string

                if type == "channel" {
                    return ContentItem(channel: self.extractChannel(from: json))
                }
                if type == "playlist" {
                    return ContentItem(playlist: self.extractChannelPlaylist(from: json))
                }
                if type == "video" {
                    return ContentItem(video: self.extractVideo(from: json))
                }

                return nil
            }

            return SearchPage(results: results, last: results.isEmpty)
        }

        configureTransformer(pathPattern("search/suggestions"), requestMethods: [.get]) { (content: Entity<JSON>) -> [String] in
            if let suggestions = content.json.dictionaryValue["suggestions"] {
                return suggestions.arrayValue.map(\.stringValue).map(\.replacingHTMLEntities)
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
            self.extractPlaylist(from: JSON(parseJSON: String(data: content.content, encoding: .utf8)!))
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

        configureTransformer(pathPattern("channels/*"), requestMethods: [.get]) { (content: Entity<JSON>) -> ChannelPage in
            self.extractChannelPage(from: content.json, forceNotLast: true)
        }

        configureTransformer(pathPattern("channels/*/videos"), requestMethods: [.get]) { (content: Entity<JSON>) -> ChannelPage in
            self.extractChannelPage(from: content.json)
        }

        configureTransformer(pathPattern("channels/*/latest"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Video] in
            content.json.dictionaryValue["videos"]?.arrayValue.map(self.extractVideo) ?? []
        }

        for type in ["latest", "playlists", "streams", "shorts", "channels", "videos", "releases", "podcasts"] {
            configureTransformer(pathPattern("channels/*/\(type)"), requestMethods: [.get]) { (content: Entity<JSON>) -> ChannelPage in
                self.extractChannelPage(from: content.json)
            }
        }

        configureTransformer(pathPattern("playlists/*"), requestMethods: [.get]) { (content: Entity<JSON>) -> ChannelPlaylist in
            self.extractChannelPlaylist(from: content.json)
        }

        configureTransformer(pathPattern("videos/*"), requestMethods: [.get]) { (content: Entity<JSON>) -> Video in
            self.extractVideo(from: content.json)
        }

        configureTransformer(pathPattern("comments/*")) { (content: Entity<JSON>) -> CommentsPage in
            let details = content.json.dictionaryValue
            let comments = details["comments"]?.arrayValue.compactMap { self.extractComment(from: $0) } ?? []
            let nextPage = details["continuation"]?.string
            let disabled = !details["error"].isNil

            return CommentsPage(comments: comments, nextPage: nextPage, disabled: disabled)
        }

        if account.token.isNil || account.token!.isEmpty {
            updateToken()
        } else {
            FeedModel.shared.onAccountChange()
            SubscribedChannelsModel.shared.onAccountChange()
            PlaylistsModel.shared.onAccountChange()
        }
    }

    func updateToken(force: Bool = false) {
        let (username, password) = AccountsModel.getCredentials(account)
        guard !account.anonymous,
              (account.token?.isEmpty ?? true) || force
        else {
            return
        }

        guard let username,
              let password,
              !username.isEmpty,
              !password.isEmpty
        else {
            NavigationModel.shared.presentAlert(
                title: "Account Error",
                message: "Remove and add your account again in Settings."
            )
            return
        }

        let presentTokenUpdateFailedAlert: (AFDataResponse<Data?>?, String?) -> Void = { response, message in
            NavigationModel.shared.presentAlert(
                title: "Account Error",
                message: message ?? "\(response?.response?.statusCode ?? -1) - \(response?.error?.errorDescription ?? "unknown")\nIf this issue persists, try removing and adding your account again in Settings."
            )
        }

        AF
            .request(login.url, method: .post, parameters: ["email": username, "password": password], encoding: URLEncoding.default)
            .redirect(using: .doNotFollow)
            .response { response in
                guard let headers = response.response?.headers,
                      let cookies = headers["Set-Cookie"]
                else {
                    presentTokenUpdateFailedAlert(response, nil)
                    return
                }

                let sidRegex = #"SID=(?<sid>[^;]*);"#
                guard let sidRegex = try? NSRegularExpression(pattern: sidRegex),
                      let match = sidRegex.matches(in: cookies, range: NSRange(cookies.startIndex..., in: cookies)).first
                else {
                    presentTokenUpdateFailedAlert(nil, String(format: "Could not extract SID from received cookies: %@".localized(), cookies))
                    return
                }

                let matchRange = match.range(withName: "sid")

                if let substringRange = Range(matchRange, in: cookies) {
                    let sid = String(cookies[substringRange])
                    AccountsModel.setToken(self.account, sid)
                    self.objectWillChange.send()
                } else {
                    presentTokenUpdateFailedAlert(nil, String(format: "Could not extract SID from received cookies: %@".localized(), cookies))
                }

                self.configure()
            }
    }

    var login: Resource {
        resource(baseURL: account.url, path: "login")
    }

    private func pathPattern(_ path: String) -> String {
        "**\(Self.basePath)/\(path)"
    }

    private func basePathAppending(_ path: String) -> String {
        "\(Self.basePath)/\(path)"
    }

    private var cookieHeader: String? {
        guard let token = account?.token, !token.isEmpty else { return nil }
        return "SID=\(token)"
    }

    var popular: Resource? {
        resource(baseURL: account.url, path: "\(Self.basePath)/popular")
    }

    func trending(country: Country, category: TrendingCategory?) -> Resource {
        resource(baseURL: account.url, path: "\(Self.basePath)/trending")
            .withParam("type", category?.type)
            .withParam("region", country.rawValue)
    }

    var home: Resource? {
        resource(baseURL: account.url, path: "/feed/subscriptions")
    }

    func feed(_ page: Int?) -> Resource? {
        resourceWithAuthCheck(baseURL: account.url, path: "\(Self.basePath)/auth/feed")
            .withParam("page", String(page ?? 1))
    }

    var feed: Resource? {
        resourceWithAuthCheck(baseURL: account.url, path: basePathAppending("auth/feed"))
    }

    var subscriptions: Resource? {
        resourceWithAuthCheck(baseURL: account.url, path: basePathAppending("auth/subscriptions"))
    }

    func subscribe(_ channelID: String, onCompletion: @escaping () -> Void = {}) {
        resourceWithAuthCheck(baseURL: account.url, path: basePathAppending("auth/subscriptions"))
            .child(channelID)
            .request(.post)
            .onCompletion { _ in onCompletion() }
    }

    func unsubscribe(_ channelID: String, onCompletion: @escaping () -> Void) {
        resourceWithAuthCheck(baseURL: account.url, path: basePathAppending("auth/subscriptions"))
            .child(channelID)
            .request(.delete)
            .onCompletion { _ in onCompletion() }
    }

    func channel(_ id: String, contentType: Channel.ContentType, data _: String?, page: String?) -> Resource {
        if page.isNil, contentType == .videos {
            return resource(baseURL: account.url, path: basePathAppending("channels/\(id)"))
        }

        var resource = resource(baseURL: account.url, path: basePathAppending("channels/\(id)/\(contentType.invidiousID)"))

        if let page, !page.isEmpty {
            resource = resource.withParam("continuation", page)
        }

        return resource
    }

    func channelByName(_: String) -> Resource? {
        nil
    }

    func channelByUsername(_: String) -> Resource? {
        nil
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

        return resourceWithAuthCheck(baseURL: account.url, path: basePathAppending("auth/playlists"))
    }

    func playlist(_ id: String) -> Resource? {
        resourceWithAuthCheck(baseURL: account.url, path: basePathAppending("auth/playlists/\(id)"))
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

        if let page {
            resource = resource.withParam("page", page)
        }

        return resource
    }

    func searchSuggestions(query: String) -> Resource {
        resource(baseURL: account.url, path: basePathAppending("search/suggestions"))
            .withParam("q", query.lowercased())
    }

    func comments(_ id: Video.ID, page: String?) -> Resource? {
        let resource = resource(baseURL: account.url, path: basePathAppending("comments/\(id)"))
        guard let page else { return resource }

        return resource.withParam("continuation", page)
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
        guard let instanceURLComponents = URLComponents(url: instance.apiURL, resolvingAgainstBaseURL: false),
              var urlComponents = URLComponents(url: asset.url, resolvingAgainstBaseURL: false) else { return nil }

        urlComponents.scheme = instanceURLComponents.scheme
        urlComponents.host = instanceURLComponents.host
        urlComponents.user = instanceURLComponents.user
        urlComponents.password = instanceURLComponents.password
        urlComponents.port = instanceURLComponents.port

        guard let url = urlComponents.url else {
            return nil
        }

        return AVURLAsset(url: url)
    }

    func extractVideo(from json: JSON) -> Video {
        let indexID: String?
        var id: Video.ID
        var published = json["publishedText"].stringValue
        var publishedAt: Date?

        if let publishedInterval = json["published"].double {
            publishedAt = Date(timeIntervalSince1970: publishedInterval)
            published = ""
        }

        let videoID = json["videoId"].stringValue

        if let index = json["indexId"].string {
            indexID = index
            id = videoID + index
        } else {
            indexID = nil
            id = videoID
        }

        let description = json["description"].stringValue
        let length = json["lengthSeconds"].doubleValue

        return Video(
            instanceID: account.instanceID,
            app: .invidious,
            instanceURL: account.instance.apiURL,
            id: id,
            videoID: videoID,
            title: json["title"].stringValue,
            author: json["author"].stringValue,
            length: length,
            published: published,
            views: json["viewCount"].intValue,
            description: description,
            genre: json["genre"].stringValue,
            channel: extractChannel(from: json),
            thumbnails: extractThumbnails(from: json),
            indexID: indexID,
            live: json["liveNow"].boolValue,
            upcoming: json["isUpcoming"].boolValue,
            short: length <= Video.shortLength && length != 0.0,
            publishedAt: publishedAt,
            likes: json["likeCount"].int,
            dislikes: json["dislikeCount"].int,
            keywords: json["keywords"].arrayValue.compactMap { $0.string },
            streams: extractStreams(from: json),
            related: extractRelated(from: json),
            chapters: createChapters(from: description, thumbnails: json),
            captions: extractCaptions(from: json)
        )
    }

    func extractChannel(from json: JSON) -> Channel {
        var thumbnailURL = json["authorThumbnails"].arrayValue.last?.dictionaryValue["url"]?.string ?? ""

        // append protocol to unproxied thumbnail URL if it's missing
        if thumbnailURL.count > 2,
           String(thumbnailURL[..<thumbnailURL.index(thumbnailURL.startIndex, offsetBy: 2)]) == "//",
           let accountUrlComponents = URLComponents(string: account.urlString)
        {
            thumbnailURL = "\(accountUrlComponents.scheme ?? "https"):\(thumbnailURL)"
        }

        let tabs = json["tabs"].arrayValue.compactMap { name in
            if let name = name.string, let type = Channel.ContentType.from(name) {
                return Channel.Tab(contentType: type, data: "")
            }

            return nil
        }

        return Channel(
            app: .invidious,
            id: json["authorId"].stringValue,
            name: json["author"].stringValue,
            bannerURL: json["authorBanners"].arrayValue.first?.dictionaryValue["url"]?.url,
            thumbnailURL: URL(string: thumbnailURL),
            description: json["description"].stringValue,
            subscriptionsCount: json["subCount"].int,
            subscriptionsText: json["subCountText"].string,
            totalViews: json["totalViews"].int,
            videos: json.dictionaryValue["latestVideos"]?.arrayValue.map(extractVideo) ?? [],
            tabs: tabs
        )
    }

    func extractChannelPlaylist(from json: JSON) -> ChannelPlaylist {
        let details = json.dictionaryValue
        return ChannelPlaylist(
            id: details["playlistId"]?.string ?? details["mixId"]?.string ?? UUID().uuidString,
            title: details["title"]?.stringValue ?? "",
            thumbnailURL: details["playlistThumbnail"]?.url,
            channel: extractChannel(from: json),
            videos: details["videos"]?.arrayValue.compactMap(extractVideo) ?? [],
            videosCount: details["videoCount"]?.int
        )
    }

    // Determines if the request requires Basic Auth credentials to be removed
    private func needsBasicAuthRemoval(for path: String) -> Bool {
        return path.hasPrefix("\(Self.basePath)/auth/")
    }

    // Creates a resource URL with consideration for removing Basic Auth credentials
    private func createResourceURL(baseURL: URL, path: String) -> URL {
        var resourceURL = baseURL

        // Remove Basic Auth credentials if required
        if needsBasicAuthRemoval(for: path), var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) {
            urlComponents.user = nil
            urlComponents.password = nil
            resourceURL = urlComponents.url ?? baseURL
        }

        return resourceURL.appendingPathComponent(path)
    }

    func resourceWithAuthCheck(baseURL: URL, path: String) -> Resource {
        let sanitizedURL = createResourceURL(baseURL: baseURL, path: path)
        return super.resource(absoluteURL: sanitizedURL)
    }

    private func extractThumbnails(from details: JSON) -> [Thumbnail] {
        details["videoThumbnails"].arrayValue.compactMap { json in
            guard let url = json["url"].url,
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let quality = json["quality"].string,
                  let accountUrlComponents = URLComponents(string: account.urlString)
            else {
                return nil
            }

            // Some instances are not configured properly and return thumbnail links
            // with an incorrect scheme or a missing port.
            components.scheme = accountUrlComponents.scheme
            components.port = accountUrlComponents.port

            // If basic HTTP authentication is used,
            // the username and password need to be prepended to the URL.
            components.user = accountUrlComponents.user
            components.password = accountUrlComponents.password

            guard let thumbnailUrl = components.url else {
                return nil
            }
            print("Final thumbnail URL: \(thumbnailUrl)")

            return Thumbnail(url: thumbnailUrl, quality: .init(rawValue: quality)!)
        }
    }

    private func createChapters(from description: String, thumbnails: JSON) -> [Chapter] {
        var chapters = extractChapters(from: description)

        if !chapters.isEmpty {
            let thumbnailsData = extractThumbnails(from: thumbnails)
            let thumbnailURL = thumbnailsData.first { $0.quality == .medium }?.url

            for chapter in chapters.indices {
                if let url = thumbnailURL {
                    chapters[chapter].image = url
                }
            }
        }
        return chapters
    }

    private static var contentItemsKeys = ["items", "videos", "latestVideos", "playlists", "relatedChannels"]

    private func extractChannelPage(from json: JSON, forceNotLast: Bool = false) -> ChannelPage {
        let nextPage = json.dictionaryValue["continuation"]?.string
        var contentItems = [ContentItem]()

        if let key = Self.contentItemsKeys.first(where: { json.dictionaryValue.keys.contains($0) }),
           let items = json.dictionaryValue[key]
        {
            contentItems = extractContentItems(from: items)
        }

        var last = false
        if !forceNotLast {
            last = nextPage?.isEmpty ?? true
        }

        return ChannelPage(
            results: contentItems,
            channel: extractChannel(from: json),
            nextPage: nextPage,
            last: last
        )
    }

    private func extractStreams(from json: JSON) -> [Stream] {
        let hls = extractHLSStreams(from: json)
        if json["liveNow"].boolValue {
            return hls
        }

        return extractFormatStreams(from: json["formatStreams"].arrayValue) +
            extractAdaptiveFormats(from: json["adaptiveFormats"].arrayValue) +
            hls
    }

    private func extractFormatStreams(from streams: [JSON]) -> [Stream] {
        streams.compactMap { stream in
            guard let streamURL = stream["url"].url else {
                return nil
            }

            return SingleAssetStream(
                instance: account.instance,
                avAsset: AVURLAsset(url: streamURL),
                resolution: Stream.Resolution.from(resolution: stream["resolution"].string ?? ""),
                kind: .stream,
                encoding: stream["encoding"].string ?? ""
            )
        }
    }

    private func extractAdaptiveFormats(from streams: [JSON]) -> [Stream] {
        let audioStreams = streams
            .filter { $0["type"].stringValue.starts(with: "audio/mp4") }
            .sorted {
                $0.dictionaryValue["bitrate"]?.int ?? 0 >
                    $1.dictionaryValue["bitrate"]?.int ?? 0
            }
        guard let audioStream = audioStreams.first else {
            return .init()
        }

        let videoStreams = streams.filter { $0["type"].stringValue.starts(with: "video/") }

        return videoStreams.compactMap { videoStream in
            guard let audioAssetURL = audioStream["url"].url,
                  let videoAssetURL = videoStream["url"].url
            else {
                return nil
            }

            return Stream(
                instance: account.instance,
                audioAsset: AVURLAsset(url: audioAssetURL),
                videoAsset: AVURLAsset(url: videoAssetURL),
                resolution: Stream.Resolution.from(resolution: videoStream["resolution"].stringValue),
                kind: .adaptive,
                encoding: videoStream["encoding"].string,
                videoFormat: videoStream["type"].string,
                bitrate: videoStream["bitrate"].int,
                requestRange: videoStream["init"].string ?? videoStream["index"].string
            )
        }
    }

    private func extractHLSStreams(from content: JSON) -> [Stream] {
        if let hlsURL = content.dictionaryValue["hlsUrl"]?.url {
            return [Stream(instance: account.instance, hlsURL: hlsURL)]
        }

        return []
    }

    private func extractRelated(from content: JSON) -> [Video] {
        content
            .dictionaryValue["recommendedVideos"]?
            .arrayValue
            .compactMap(extractVideo(from:)) ?? []
    }

    private func extractPlaylist(from content: JSON) -> Playlist {
        let id = content["playlistId"].stringValue
        return Playlist(
            id: id,
            title: content["title"].stringValue,
            visibility: content["isListed"].boolValue ? .public : .private,
            editable: id.starts(with: "IV"),
            updated: content["updated"].doubleValue,
            videos: content["videos"].arrayValue.map { extractVideo(from: $0) }
        )
    }

    private func extractComment(from content: JSON) -> Comment? {
        let details = content.dictionaryValue
        let author = details["author"]?.string ?? ""
        let channelId = details["authorId"]?.string ?? UUID().uuidString
        let authorAvatarURL = details["authorThumbnails"]?.arrayValue.last?.dictionaryValue["url"]?.string ?? ""
        let htmlContent = details["contentHtml"]?.string ?? ""
        let decodedContent = decodeHtml(htmlContent)
        return Comment(
            id: UUID().uuidString,
            author: author,
            authorAvatarURL: authorAvatarURL,
            time: details["publishedText"]?.string ?? "",
            pinned: false,
            hearted: false,
            likeCount: details["likeCount"]?.int ?? 0,
            text: decodedContent,
            repliesPage: details["replies"]?.dictionaryValue["continuation"]?.string,
            channel: Channel(app: .invidious, id: channelId, name: author)
        )
    }

    private func decodeHtml(_ htmlEncodedString: String) -> String {
        if let data = htmlEncodedString.data(using: .utf8) {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
            if let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
                return attributedString.string
            }
        }
        return htmlEncodedString
    }

    private func extractCaptions(from content: JSON) -> [Captions] {
        content["captions"].arrayValue.compactMap { details in
            guard let url = URL(string: details["url"].stringValue, relativeTo: account.url) else { return nil }

            return Captions(
                label: details["label"].stringValue,
                code: details["language_code"].stringValue,
                url: url
            )
        }
    }

    private func extractContentItems(from json: JSON) -> [ContentItem] {
        json.arrayValue.compactMap { extractContentItem(from: $0) }
    }

    private func extractContentItem(from json: JSON) -> ContentItem? {
        let type = json.dictionaryValue["type"]?.string

        if type == "channel" {
            return ContentItem(channel: extractChannel(from: json))
        }
        if type == "playlist" {
            return ContentItem(playlist: extractChannelPlaylist(from: json))
        }
        if type == "video" {
            return ContentItem(video: extractVideo(from: json))
        }

        return nil
    }
}

extension Channel.ContentType {
    var invidiousID: String {
        switch self {
        case .livestreams:
            return "streams"
        default:
            return rawValue
        }
    }
}
