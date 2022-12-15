import AVFoundation
import Defaults
import Foundation
import SwiftyJSON

struct Channel: Identifiable, Hashable {
    enum ContentType: String, Identifiable, CaseIterable {
        case videos
        case playlists
        case livestreams
        case shorts
        case channels

        var id: String {
            rawValue
        }

        var description: String {
            switch self {
            case .livestreams:
                return "Live Streams".localized()
            default:
                return rawValue.capitalized.localized()
            }
        }

        var contentItemType: ContentItem.ContentType {
            switch self {
            case .videos:
                return .video
            case .playlists:
                return .playlist
            case .livestreams:
                return .video
            case .shorts:
                return .video
            case .channels:
                return .channel
            }
        }

        var systemImage: String {
            switch self {
            case .videos:
                return "video"
            case .playlists:
                return "list.and.film"
            case .livestreams:
                return "dot.radiowaves.left.and.right"
            case .shorts:
                return "1.square"
            case .channels:
                return "person.3"
            }
        }
    }

    struct Tab: Identifiable, Hashable {
        var contentType: ContentType
        var data: String

        var id: String {
            contentType.id
        }
    }

    var app: VideosApp
    var instanceID: Instance.ID?
    var instanceURL: URL?

    var id: String
    var name: String
    var bannerURL: URL?
    var thumbnailURL: URL?
    var description = ""

    var subscriptionsCount: Int?
    var subscriptionsText: String?

    var totalViews: Int?
    var verified: Bool? // swiftlint:disable discouraged_optional_boolean

    var videos = [Video]()
    var tabs = [Tab]()

    var detailsLoaded: Bool {
        !subscriptionsString.isNil
    }

    var subscriptionsString: String? {
        if let subscriptionsCount, subscriptionsCount > 0 {
            return subscriptionsCount.formattedAsAbbreviation()
        }

        return subscriptionsText
    }

    var totalViewsString: String? {
        guard let totalViews, totalViews > 0 else { return nil }

        return totalViews.formattedAsAbbreviation()
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var contentItem: ContentItem {
        ContentItem(channel: self)
    }

    func hasData(for contentType: ContentType) -> Bool {
        guard contentType != .videos, contentType != .playlists else { return true }
        return tabs.contains { $0.contentType == contentType }
    }

    var cacheKey: String {
        switch app {
        case .local:
            return id
        case .invidious:
            return "youtube-\(id)"
        case .piped:
            return "youtube-\(id)"
        case .peerTube:
            return "peertube-\(instanceURL?.absoluteString ?? "unknown-instance")-\(id)"
        }
    }

    var hasExtendedDetails: Bool {
        thumbnailURL != nil
    }

    var thumbnailURLOrCached: URL? {
        thumbnailURL ?? ChannelsCacheModel.shared.retrieve(cacheKey)?.thumbnailURL
    }

    var json: JSON {
        [
            "app": app.rawValue,
            "id": id,
            "name": name,
            "thumbnailURL": thumbnailURL?.absoluteString ?? "",
            "videos": videos.map { $0.json.object }
        ]
    }

    static func from(_ json: JSON) -> Self {
        .init(
            app: VideosApp(rawValue: json["app"].stringValue) ?? .local,
            id: json["id"].stringValue,
            name: json["name"].stringValue,
            thumbnailURL: json["thumbnailURL"].url,
            videos: json["videos"].arrayValue.map { Video.from($0) }
        )
    }
}
