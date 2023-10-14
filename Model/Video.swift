import Alamofire
import AVKit
import Foundation
import SwiftUI
import SwiftyJSON

struct Video: Identifiable, Equatable, Hashable {
    static let shortLength = 61.0

    enum VideoID {
        static func isValid(_ id: Video.ID) -> Bool {
            isYouTube(id) || isPeerTube(id)
        }

        static func isYouTube(_ id: Video.ID) -> Bool {
            id.count == 11
        }

        static func isPeerTube(_ id: Video.ID) -> Bool {
            id.count == 36
        }
    }

    var instanceID: Instance.ID?
    var app: VideosApp
    var instanceURL: URL?

    var id: String
    var videoID: String
    var videoURL: URL?
    var title: String
    var thumbnails: [Thumbnail]
    var author: String
    var length: TimeInterval
    var published: String
    var views: Int
    var description: String?
    var genre: String?

    // index used when in the Playlist
    var indexID: String?

    var live: Bool
    var upcoming: Bool
    var short: Bool

    var streams = [Stream]()

    var publishedAt: Date?
    var likes: Int?
    var dislikes: Int?
    var keywords = [String]()

    var channel: Channel

    var related = [Self]()
    var chapters = [Chapter]()

    var captions = [Captions]()

    init(
        instanceID: Instance.ID? = nil,
        app: VideosApp,
        instanceURL: URL? = nil,
        id: String? = nil,
        videoID: String,
        videoURL: URL? = nil,
        title: String = "",
        author: String = "",
        length: TimeInterval = .zero,
        published: String = "",
        views: Int = 0,
        description: String? = nil,
        genre: String? = nil,
        channel: Channel? = nil,
        thumbnails: [Thumbnail] = [],
        indexID: String? = nil,
        live: Bool = false,
        upcoming: Bool = false,
        short: Bool = false,
        publishedAt: Date? = nil,
        likes: Int? = nil,
        dislikes: Int? = nil,
        keywords: [String] = [],
        streams: [Stream] = [],
        related: [Self] = [],
        chapters: [Chapter] = [],
        captions: [Captions] = []
    ) {
        self.instanceID = instanceID
        self.app = app
        self.instanceURL = instanceURL
        self.id = id ?? UUID().uuidString
        self.videoID = videoID
        self.videoURL = videoURL
        self.title = title
        self.author = author
        self.length = length
        self.published = published
        self.views = views
        self.description = description
        self.genre = genre
        self.channel = channel ?? .init(app: app, id: "", name: "")
        self.thumbnails = thumbnails
        self.indexID = indexID
        self.live = live
        self.upcoming = upcoming
        self.short = short
        self.publishedAt = publishedAt
        self.likes = likes
        self.dislikes = dislikes
        self.keywords = keywords
        self.streams = streams
        self.related = related
        self.chapters = chapters
        self.captions = captions
    }

    static func local(_ url: URL) -> Self {
        Self(
            app: .local,
            videoID: url.absoluteString,
            streams: [.init(localURL: url)]
        )
    }

    var cacheKey: String {
        switch app {
        case .local:
            return videoID
        case .invidious:
            return "youtube-\(videoID)"
        case .piped:
            return "youtube-\(videoID)"
        case .peerTube:
            return "peertube-\(instanceURL?.absoluteString ?? "unknown-instance")-\(videoID)"
        }
    }

    var json: JSON {
        let dateFormatter = ISO8601DateFormatter()
        let publishedAt = self.publishedAt == nil ? "" : dateFormatter.string(from: self.publishedAt!)
        return [
            "instanceID": instanceID ?? "",
            "app": app.rawValue,
            "instanceURL": instanceURL?.absoluteString ?? "",
            "id": id,
            "videoID": videoID,
            "videoURL": videoURL?.absoluteString ?? "",
            "title": title,
            "author": author,
            "length": length,
            "published": published,
            "views": views,
            "description": description ?? "",
            "genre": genre ?? "",
            "channel": channel.json.object,
            "thumbnails": thumbnails.compactMap { $0.json.object },
            "indexID": indexID ?? "",
            "live": live,
            "upcoming": upcoming,
            "short": short,
            "publishedAt": publishedAt
        ]
    }

    static func from(_ json: JSON) -> Self {
        let dateFormatter = ISO8601DateFormatter()

        return Self(
            instanceID: json["instanceID"].stringValue,
            app: .init(rawValue: json["app"].stringValue) ?? AccountsModel.shared.current.app ?? .local,
            instanceURL: URL(string: json["instanceURL"].stringValue) ?? AccountsModel.shared.current.instance.apiURL,
            id: json["id"].stringValue,
            videoID: json["videoID"].stringValue,
            videoURL: json["videoURL"].url,
            title: json["title"].stringValue,
            author: json["author"].stringValue,
            length: json["length"].doubleValue,
            published: json["published"].stringValue,
            views: json["views"].intValue,
            description: json["description"].string,
            genre: json["genre"].string,
            channel: Channel.from(json["channel"]),
            thumbnails: json["thumbnails"].arrayValue.compactMap { Thumbnail.from($0) },
            indexID: json["indexID"].stringValue,
            live: json["live"].boolValue,
            upcoming: json["upcoming"].boolValue,
            short: json["short"].boolValue,
            publishedAt: dateFormatter.date(from: json["publishedAt"].stringValue)
        )
    }

    var instance: Instance! {
        if let instance = InstancesModel.shared.find(instanceID) {
            return instance
        }

        if let url = instanceURL?.absoluteString {
            return Instance(app: app, id: instanceID, apiURLString: url, proxiesVideos: false)
        }

        return nil
    }

    var isLocal: Bool {
        !VideoID.isValid(videoID) && videoID != Self.fixtureID
    }

    var displayTitle: String {
        if isLocal {
            return localStreamFileName ?? localStream?.description ?? title
        }

        return title
    }

    var displayAuthor: String {
        if isLocal, localStreamIsRemoteURL {
            return remoteUrlHost ?? "Unknown"
        }

        return author
    }

    var publishedDate: String? {
        (published.isEmpty || published == "0 seconds ago") ? publishedAt?.timeIntervalSince1970.formattedAsRelativeTime() : published
    }

    var viewsCount: String? {
        views != 0 ? views.formattedAsAbbreviation() : nil
    }

    var likesCount: String? {
        guard let likes else {
            return nil
        }

        return likes.formattedAsAbbreviation()
    }

    var dislikesCount: String? {
        guard let dislikes else { return nil }

        return dislikes.formattedAsAbbreviation()
    }

    func thumbnailURL(quality: Thumbnail.Quality) -> URL? {
        thumbnails.first { $0.quality == quality }?.url
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        let videoIDIsEqual = lhs.videoID == rhs.videoID

        if !lhs.indexID.isNil, !rhs.indexID.isNil {
            return videoIDIsEqual && lhs.indexID == rhs.indexID
        }

        return videoIDIsEqual
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var watchFetchRequest: FetchRequest<Watch> {
        FetchRequest<Watch>(
            entity: Watch.entity(),
            sortDescriptors: [],
            predicate: NSPredicate(format: "videoID = %@", videoID)
        )
    }

    var localStream: Stream? {
        guard isLocal else { return nil }
        return streams.first
    }

    var localStreamImageSystemName: String {
        guard localStream != nil else { return "" }

        if localStreamIsDirectory {
            return "folder"
        }
        if localStreamIsFile {
            return "doc"
        }

        return "globe"
    }

    var localStreamIsFile: Bool {
        guard let url = localStream?.localURL else { return false }
        return url.isFileURL
    }

    var localStreamIsRemoteURL: Bool {
        guard let url = localStream?.localURL else { return false }
        return url.isFileURL
    }

    var localStreamIsDirectory: Bool {
        guard let localStream else { return false }
        #if os(iOS)
            return DocumentsModel.shared.isDirectory(localStream.localURL)
        #else
            return false
        #endif
    }

    var remoteUrlHost: String? {
        localStreamURLComponents?.host
    }

    var localStreamFileName: String? {
        guard let path = localStream?.localURL?.lastPathComponent else { return nil }

        if let localStreamFileExtension {
            return String(path.dropLast(localStreamFileExtension.count + 1))
        }
        return String(path)
    }

    var localStreamFileExtension: String? {
        guard let path = localStreamURLComponents?.path else { return nil }
        return path.contains(".") ? path.components(separatedBy: ".").last?.uppercased() : nil
    }

    var isShareable: Bool {
        !isLocal || localStreamIsRemoteURL
    }

    private var localStreamURLComponents: URLComponents? {
        guard let localStream else { return nil }
        return URLComponents(url: localStream.localURL, resolvingAgainstBaseURL: false)
    }
}
