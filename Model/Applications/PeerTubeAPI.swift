import Alamofire
import AVKit
import Defaults
import Foundation
import Siesta
import SwiftyJSON

final class PeerTubeAPI: Service, ObservableObject, VideosAPI {
    static let basePath = "/api/v1"

    @Published var account: Account!

    @Published var validInstance = true

    var signedIn: Bool {
        guard let account else { return false }

        return !account.anonymous && !(account.token?.isEmpty ?? true)
    }

    static func withAnonymousAccountForInstanceURL(_ url: URL) -> PeerTubeAPI {
        .init(account: Instance(app: .peerTube, apiURLString: url.absoluteString).anonymousAccount)
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
        guard signedIn, !(account.token?.isEmpty ?? true) else {
            return
        }

        feed(1)?
            .load()
            .onFailure { _ in
                self.updateToken(force: true)
            }
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

        configureTransformer(pathPattern("videos"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Video] in
            content.json.dictionaryValue["data"]?.arrayValue.map(self.extractVideo) ?? []
        }

        configureTransformer(pathPattern("search/videos"), requestMethods: [.get]) { (content: Entity<JSON>) -> SearchPage in
            let results = content.json.dictionaryValue["data"]?.arrayValue.compactMap { json -> ContentItem in .init(video: self.extractVideo(from: json)) } ?? []
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

        configureTransformer(pathPattern("channels/*"), requestMethods: [.get]) { (content: Entity<JSON>) -> Channel in
            self.extractChannel(from: content.json)
        }

        configureTransformer(pathPattern("channels/*/latest"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Video] in
            content.json.arrayValue.map(self.extractVideo)
        }

        configureTransformer(pathPattern("channels/*/playlists"), requestMethods: [.get]) { (content: Entity<JSON>) -> [ContentItem] in
            let playlists = (content.json.dictionaryValue["playlists"]?.arrayValue ?? []).compactMap { self.extractChannelPlaylist(from: $0) }
            return ContentItem.array(of: playlists)
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

        updateToken()
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

    func trending(country _: Country, category _: TrendingCategory?) -> Resource {
        resource(baseURL: account.url, path: "\(Self.basePath)/videos")
            .withParam("isLocal", "true")
//            .withParam("type", category?.name)
//            .withParam("region", country.rawValue)
    }

    var home: Resource? {
        resource(baseURL: account.url, path: "/feed/subscriptions")
    }

    func feed(_ page: Int?) -> Resource? {
        resource(baseURL: account.url, path: "\(Self.basePath)/auth/feed")
            .withParam("page", String(page ?? 1))
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

    func channel(_ id: String, contentType: Channel.ContentType, data _: String?, page _: String?) -> Resource {
        if contentType == .playlists {
            return resource(baseURL: account.url, path: basePathAppending("channels/\(id)/playlists"))
        }
        return resource(baseURL: account.url, path: basePathAppending("channels/\(id)"))
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

    func search(_ query: SearchQuery, page _: String?) -> Resource {
        resource(baseURL: account.url, path: basePathAppending("search/videos"))
            .withParam("search", query.query)
//            .withParam("sort_by", query.sortBy.parameter)
//            .withParam("type", "all")
//
//        if let date = query.date, date != .any {
//            resource = resource.withParam("date", date.rawValue)
//        }
//
//        if let duration = query.duration, duration != .any {
//            resource = resource.withParam("duration", duration.rawValue)
//        }
//
//        if let page {
//            resource = resource.withParam("page", page)
//        }

//        return resource
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

    static func proxiedAsset(instance: Instance, asset: AVURLAsset) -> AVURLAsset? {
        guard let instanceURLComponents = URLComponents(string: instance.apiURLString),
              var urlComponents = URLComponents(url: asset.url, resolvingAgainstBaseURL: false) else { return nil }

        urlComponents.scheme = instanceURLComponents.scheme
        urlComponents.host = instanceURLComponents.host

        guard let url = urlComponents.url else {
            return nil
        }

        return AVURLAsset(url: url)
    }

    func extractVideo(from json: JSON) -> Video {
        let id = json["uuid"].stringValue
        let url = json["url"].url
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let publishedAt = dateFormatter.date(from: json["publishedAt"].stringValue)

        return Video(
            instanceID: account.instanceID,
            app: .peerTube,
            instanceURL: account.instance.apiURL,
            id: id,
            videoID: id,
            videoURL: url,
            title: json["name"].stringValue,
            author: json["channel"].dictionaryValue["name"]?.stringValue ?? "",
            length: json["duration"].doubleValue,
            views: json["views"].intValue,
            description: json["description"].stringValue,
            channel: extractChannel(from: json["channel"]),
            thumbnails: extractThumbnails(from: json),
            live: json["isLive"].boolValue,
            publishedAt: publishedAt,
            likes: json["likes"].int,
            dislikes: json["dislikes"].int,
            streams: extractStreams(from: json)
//            related: extractRelated(from: json),
//            chapters: extractChapters(from: description),
//            captions: extractCaptions(from: json)
        )
    }

    func extractChannel(from json: JSON) -> Channel {
        Channel(
            app: .peerTube,
            id: json["id"].stringValue,
            name: json["name"].stringValue
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

    private func extractThumbnails(from details: JSON) -> [Thumbnail] {
        if let thumbnailPath = details["thumbnailPath"].string {
            return [Thumbnail(url: URL(string: thumbnailPath, relativeTo: account.url)!, quality: .medium)]
        }
        return []
    }

    private func extractStreams(from json: JSON) -> [Stream] {
        let hls = extractHLSStreams(from: json)

        if json["isLive"].boolValue {
            return hls
        }

        return extractFormatStreams(from: json) +
            extractAdaptiveFormats(from: json) +
            hls
    }

    private func extractFormatStreams(from json: JSON) -> [Stream] {
        var streams = [Stream]()
        if let fileURL = json.dictionaryValue["streamingPlaylists"]?.arrayValue.first?
            .dictionaryValue["files"]?.arrayValue.first?
            .dictionaryValue["fileUrl"]?.url
        {
            let resolution = Stream.Resolution.predefined(.hd720p30)
            streams.append(SingleAssetStream(instance: account.instance, avAsset: AVURLAsset(url: fileURL), resolution: resolution, kind: .stream))
        }

        return streams
    }

    private func extractAdaptiveFormats(from json: JSON) -> [Stream] {
        json.dictionaryValue["files"]?.arrayValue.compactMap { file in
            if let resolution = file.dictionaryValue["resolution"]?.dictionaryValue["label"]?.stringValue, let url = file.dictionaryValue["fileUrl"]?.url {
                return SingleAssetStream(instance: account.instance, avAsset: AVURLAsset(url: url), resolution: Stream.Resolution.from(resolution: resolution), kind: .adaptive, videoFormat: "mp4")
            }

            return nil
        } ?? []
    }

    private func extractHLSStreams(from content: JSON) -> [Stream] {
        if let hlsURL = content.dictionaryValue["streamingPlaylists"]?.arrayValue.first?.dictionaryValue["playlistUrl"]?.url {
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
        return Comment(
            id: UUID().uuidString,
            author: author,
            authorAvatarURL: authorAvatarURL,
            time: details["publishedText"]?.string ?? "",
            pinned: false,
            hearted: false,
            likeCount: details["likeCount"]?.int ?? 0,
            text: details["content"]?.string ?? "",
            repliesPage: details["replies"]?.dictionaryValue["continuation"]?.string,
            channel: Channel(app: .peerTube, id: channelId, name: author)
        )
    }

    private func extractCaptions(from content: JSON) -> [Captions] {
        content["captions"].arrayValue.compactMap { _ in
            nil
//            let baseURL = account.url
//            guard let url = URL(string: baseURL + details["url"].stringValue) else { return nil }
//
//            return Captions(
//                label: details["label"].stringValue,
//                code: details["language_code"].stringValue,
//                url: url
//            )
        }
    }
}
