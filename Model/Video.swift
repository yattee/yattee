import Alamofire
import AVKit
import Foundation
import SwiftUI
import SwiftyJSON

struct Video: Identifiable, Equatable, Hashable {
    enum VideoID {
        static func isValid(_ id: Video.ID) -> Bool {
            id.count == 11
        }
    }

    let id: String
    let videoID: String
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

    var streams = [Stream]()

    var publishedAt: Date?
    var likes: Int?
    var dislikes: Int?
    var keywords = [String]()

    var channel: Channel

    var related = [Video]()
    var chapters = [Chapter]()

    var captions = [Captions]()

    init(
        id: String? = nil,
        videoID: String,
        title: String = "",
        author: String = "",
        length: TimeInterval = .zero,
        published: String = "",
        views: Int = 0,
        description: String? = nil,
        genre: String? = nil,
        channel: Channel = .init(id: "", name: ""),
        thumbnails: [Thumbnail] = [],
        indexID: String? = nil,
        live: Bool = false,
        upcoming: Bool = false,
        publishedAt: Date? = nil,
        likes: Int? = nil,
        dislikes: Int? = nil,
        keywords: [String] = [],
        streams: [Stream] = [],
        related: [Video] = [],
        chapters: [Chapter] = [],
        captions: [Captions] = []
    ) {
        self.id = id ?? UUID().uuidString
        self.videoID = videoID
        self.title = title
        self.author = author
        self.length = length
        self.published = published
        self.views = views
        self.description = description
        self.genre = genre
        self.channel = channel
        self.thumbnails = thumbnails
        self.indexID = indexID
        self.live = live
        self.upcoming = upcoming
        self.publishedAt = publishedAt
        self.likes = likes
        self.dislikes = dislikes
        self.keywords = keywords
        self.streams = streams
        self.related = related
        self.chapters = chapters
        self.captions = captions
    }

    static func local(_ url: URL) -> Video {
        Video(
            videoID: url.absoluteString,
            streams: [.init(localURL: url)]
        )
    }

    var isLocal: Bool {
        !VideoID.isValid(videoID)
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
        (published.isEmpty || published == "0 seconds ago") ? nil : published
    }

    var viewsCount: String? {
        views != 0 ? views.formattedAsAbbreviation() : nil
    }

    var likesCount: String? {
        guard (likes ?? 0) > 0 else {
            return nil
        }

        return likes?.formattedAsAbbreviation()
    }

    var dislikesCount: String? {
        guard (dislikes ?? 0) > 0 else {
            return nil
        }

        return dislikes?.formattedAsAbbreviation()
    }

    func thumbnailURL(quality: Thumbnail.Quality) -> URL? {
        thumbnails.first { $0.quality == quality }?.url
    }

    static func == (lhs: Video, rhs: Video) -> Bool {
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

    var localStreamIsFile: Bool {
        guard let localStream else { return false }
        return localStream.localURL.isFileURL
    }

    var localStreamIsRemoteURL: Bool {
        guard let localStream else { return false }
        return !localStream.localURL.isFileURL
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

    private var localStreamURLComponents: URLComponents? {
        guard let localStream else { return nil }
        return URLComponents(url: localStream.localURL, resolvingAgainstBaseURL: false)
    }
}
