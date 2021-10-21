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
            content.json.arrayValue.map(Video.init)
        }

        configureTransformer(pathPattern("trending"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Video] in
            content.json.arrayValue.map(Video.init)
        }

        configureTransformer(pathPattern("search"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Video] in
            content.json.arrayValue.map(Video.init)
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
                return feedVideos.arrayValue.map(Video.init)
            }

            return []
        }

        configureTransformer(pathPattern("auth/subscriptions"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Channel] in
            content.json.arrayValue.map(Channel.init)
        }

        configureTransformer(pathPattern("channels/*"), requestMethods: [.get]) { (content: Entity<JSON>) -> Channel in
            Channel(json: content.json)
        }

        configureTransformer(pathPattern("channels/*/latest"), requestMethods: [.get]) { (content: Entity<JSON>) -> [Video] in
            content.json.arrayValue.map(Video.init)
        }

        configureTransformer(pathPattern("videos/*"), requestMethods: [.get]) { (content: Entity<JSON>) -> Video in
            Video(content.json)
        }
    }

    fileprivate func pathPattern(_ path: String) -> String {
        "**\(InvidiousAPI.basePath)/\(path)"
    }

    fileprivate func basePathAppending(_ path: String) -> String {
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

    func search(_ query: SearchQuery) -> Resource {
        var resource = resource(baseURL: account.url, path: basePathAppending("search"))
            .withParam("q", searchQuery(query.query))
            .withParam("sort_by", query.sortBy.parameter)

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
}
