import Defaults
import Foundation
import Siesta
import SwiftyJSON

final class InvidiousAPI: Service {
    static let shared = InvidiousAPI()

    static let instance = "https://invidious.home.arekf.net"

    static func proxyURLForAsset(_ url: String) -> URL? {
        guard let instanceURLComponents = URLComponents(string: InvidiousAPI.instance),
              var urlComponents = URLComponents(string: url) else { return nil }

        urlComponents.scheme = instanceURLComponents.scheme
        urlComponents.host = instanceURLComponents.host

        return urlComponents.url
    }

    init() {
        SiestaLog.Category.enabled = .common

        let SwiftyJSONTransformer =
            ResponseContentTransformer(transformErrors: true) { JSON($0.content as AnyObject) }

        super.init(baseURL: "\(InvidiousAPI.instance)/api/v1")

        configure {
            $0.pipeline[.parsing].add(SwiftyJSONTransformer, contentTypes: ["*/json"])
        }

        configure("/auth/**") {
            $0.headers["Cookie"] = self.authHeader
        }

        configure("**", requestMethods: [.post]) {
            $0.pipeline[.parsing].removeTransformers()
        }

        configureTransformer("/popular", requestMethods: [.get]) { (content: Entity<JSON>) -> [Video] in
            content.json.arrayValue.map(Video.init)
        }

        configureTransformer("/trending", requestMethods: [.get]) { (content: Entity<JSON>) -> [Video] in
            content.json.arrayValue.map(Video.init)
        }

        configureTransformer("/search", requestMethods: [.get]) { (content: Entity<JSON>) -> [Video] in
            content.json.arrayValue.map(Video.init)
        }

        configureTransformer("/auth/playlists", requestMethods: [.get]) { (content: Entity<JSON>) -> [Playlist] in
            content.json.arrayValue.map(Playlist.init)
        }

        configureTransformer("/auth/playlists", requestMethods: [.post, .patch]) { (content: Entity<Data>) -> Playlist in
            // hacky, to verify if possible to get it in easier way
            Playlist(JSON(parseJSON: String(data: content.content, encoding: .utf8)!))
        }

        configureTransformer("/auth/feed", requestMethods: [.get]) { (content: Entity<JSON>) -> [Video] in
            if let feedVideos = content.json.dictionaryValue["videos"] {
                return feedVideos.arrayValue.map { Video($0) }
            }

            return []
        }

        configureTransformer("/channels/*", requestMethods: [.get]) { (content: Entity<JSON>) -> [Video] in
            if let channelVideos = content.json.dictionaryValue["latestVideos"] {
                return channelVideos.arrayValue.map { Video($0) }
            }

            return []
        }

        configureTransformer("/videos/*", requestMethods: [.get]) { (content: Entity<JSON>) -> Video in
            Video(content.json)
        }
    }

    var authHeader: String? = "SID=\(Profile().sid)"

    var popular: Resource {
        resource("/popular")
    }

    func trending(category: TrendingCategory, country: Country) -> Resource {
        resource("/trending")
            .withParam("type", category.name)
            .withParam("region", country.rawValue)
    }

    var subscriptions: Resource {
        resource("/auth/feed")
    }

    func channelVideos(_ id: String) -> Resource {
        resource("/channels/\(id)")
    }

    func video(_ id: String) -> Resource {
        resource("/videos/\(id)")
    }

    var playlists: Resource {
        resource("/auth/playlists")
    }

    func playlist(_ id: String) -> Resource {
        resource("/auth/playlists/\(id)")
    }

    func search(_ query: SearchQuery) -> Resource {
        var resource = resource("/search")
            .withParam("q", searchQuery(query.query))
            .withParam("sort_by", query.sortBy.parameter)

        if let date = query.date?.rawValue {
            resource = resource.withParam("date", date)
        }

        if let duration = query.duration?.rawValue {
            resource = resource.withParam("duration", duration)
        }

        return resource
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
