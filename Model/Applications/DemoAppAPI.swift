import AVFoundation
import Foundation
import Siesta
import SwiftyJSON

final class DemoAppAPI: Service, ObservableObject, VideosAPI {
    static var url = "https://r.yattee.stream/demo"

    var account: Account! {
        .init(
            id: UUID().uuidString,
            app: .demoApp,
            name: "Demo",
            url: Self.url,
            anonymous: true
        )
    }

    var signedIn: Bool {
        true
    }

    init() {
        super.init()

        configure()
    }

    func configure() {
        configure {
            $0.pipeline[.parsing].add(SwiftyJSONTransformer, contentTypes: ["*/json"])
        }

        configureTransformer(pathPattern("channels/*"), requestMethods: [.get]) { (content: Entity<Any>) -> Channel? in
            self.extractChannel(from: content.json)
        }

        configureTransformer(pathPattern("search*"), requestMethods: [.get]) { (content: Entity<Any>) -> SearchPage in
            let nextPage = content.json.dictionaryValue["nextpage"]?.string
            return SearchPage(
                results: self.extractContentItems(from: content.json.dictionaryValue["items"]!),
                nextPage: nextPage,
                last: nextPage == "null"
            )
        }

        configureTransformer(pathPattern("suggestions*")) { (content: Entity<JSON>) -> [String] in
            content.json.arrayValue.map(String.init)
        }

        configureTransformer(pathPattern("videos/*")) { (content: Entity<JSON>) -> Video? in
            self.extractVideo(from: content.json)
        }

        configureTransformer(pathPattern("trending*")) { (content: Entity<JSON>) -> [Video] in
            self.extractVideos(from: content.json)
        }
    }

    func channel(_ channel: String) -> Resource {
        resource(baseURL: Self.url, path: "/channels/\(channel).json")
    }

    func channelByName(_: String) -> Resource? {
        resource(baseURL: Self.url, path: "")
    }

    func channelByUsername(_: String) -> Resource? {
        resource(baseURL: Self.url, path: "")
    }

    func channelVideos(_ id: String) -> Resource {
        resource(baseURL: Self.url, path: "/channels/\(id).json")
    }

    func trending(country _: Country, category _: TrendingCategory?) -> Resource {
        resource(baseURL: Self.url, path: "/trending.json")
    }

    func search(_ query: SearchQuery, page: String?) -> Resource {
        resource(baseURL: Self.url, path: "/search.json")
            .withParam("q", query.query)
            .withParam("p", page)
    }

    func searchSuggestions(query _: String) -> Resource {
        resource(baseURL: Self.url, path: "/suggestions.json")
    }

    func video(_ id: Video.ID) -> Resource {
        resource(baseURL: Self.url, path: "/videos/\(id).json")
    }

    var subscriptions: Resource?

    var feed: Resource?

    var home: Resource?

    var popular: Resource?

    var playlists: Resource?

    func subscribe(_: String, onCompletion _: @escaping () -> Void) {}

    func unsubscribe(_: String, onCompletion _: @escaping () -> Void) {}

    func playlist(_: String) -> Resource? {
        resource(baseURL: Self.url, path: "")
    }

    func playlistVideo(_: String, _: String) -> Resource? {
        resource(baseURL: Self.url, path: "")
    }

    func playlistVideos(_: String) -> Resource? {
        resource(baseURL: Self.url, path: "")
    }

    func addVideoToPlaylist(_: String, _: String, onFailure _: @escaping (RequestError) -> Void, onSuccess _: @escaping () -> Void) {}

    func removeVideoFromPlaylist(_: String, _: String, onFailure _: @escaping (RequestError) -> Void, onSuccess _: @escaping () -> Void) {}

    func playlistForm(_: String, _: String, playlist _: Playlist?, onFailure _: @escaping (RequestError) -> Void, onSuccess _: @escaping (Playlist?) -> Void) {}

    func deletePlaylist(_: Playlist, onFailure _: @escaping (RequestError) -> Void, onSuccess _: @escaping () -> Void) {}

    func channelPlaylist(_: String) -> Resource? {
        resource(baseURL: Self.url, path: "")
    }

    func comments(_: Video.ID, page _: String?) -> Resource? {
        resource(baseURL: Self.url, path: "")
    }

    private func pathPattern(_ path: String) -> String {
        "**\(Self.url)/\(path)"
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

    private func extractVideos(from content: JSON) -> [Video] {
        content.arrayValue.compactMap(extractVideo(from:))
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
            related: extractRelated(from: content)
        )
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

    private func extractID(from content: JSON) -> Video.ID {
        content.dictionaryValue["url"]?.string?.components(separatedBy: "?v=").last ??
            extractThumbnailURL(from: content)?.relativeString.components(separatedBy: "/")[5].replacingFirstOccurrence(of: ".png", with: "") ?? ""
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

        let linkRegex = #"(<a\s+(?:[^>]*?\s+)?href=\"[^"]*\">[^<]*<\/a>)"#
        let hrefRegex = #"href=\"([^"]*)\">"#
        guard let hrefRegex = try? NSRegularExpression(pattern: hrefRegex) else { return description }

        description = description.replacingMatches(regex: linkRegex) { matchingGroup in
            let results = hrefRegex.matches(in: matchingGroup, range: NSRange(matchingGroup.startIndex..., in: matchingGroup))

            if let result = results.first {
                if let swiftRange = Range(result.range(at: 1), in: matchingGroup) {
                    return String(matchingGroup[swiftRange])
                }
            }

            return matchingGroup
        }

        description = description.replacingOccurrences(of: "&amp;", with: "&")

        description = description.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression,
            range: nil
        )

        return description
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
                        instance: account.instance,
                        audioAsset: audioAsset,
                        videoAsset: videoAsset,
                        resolution: resolution,
                        kind: .adaptive,
                        videoFormat: videoFormat
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

    private func extractThumbnailURL(from content: JSON) -> URL? {
        content.dictionaryValue["thumbnail"]?.url ?? content.dictionaryValue["thumbnailUrl"]?.url
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
        default:
            return nil
        }

        return nil
    }

    private func extractContentItems(from content: JSON) -> [ContentItem] {
        content.arrayValue.compactMap { extractContentItem(from: $0) }
    }
}
