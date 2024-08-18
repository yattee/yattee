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
        case releases
        case podcasts

        static func from(_ name: String) -> Self? {
            let rawValueMatch = allCases.first { $0.rawValue == name }
            guard rawValueMatch.isNil else { return rawValueMatch! }

            if name == "streams" { return .livestreams }

            return nil
        }

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
            case .releases:
                return "square.stack"
            case .podcasts:
                return "radio"
            }
        }

        var alwaysAvailable: Bool {
            self == .videos || self == .playlists
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
    // swiftlint:disable discouraged_optional_boolean
    var verified: Bool?
    // swiftlint:enable discouraged_optional_boolean

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
        tabs.contains { $0.contentType == contentType }
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
        thumbnailURL ?? ChannelsCacheModel.shared.retrieve(cacheKey)?.channel?.thumbnailURL
    }

    var json: JSON {
        [
            "app": app.rawValue,
            "id": id,
            "name": name,
            "bannerURL": bannerURL?.absoluteString as Any,
            "thumbnailURL": thumbnailURL?.absoluteString as Any,
            "description": description,
            "subscriptionsCount": subscriptionsCount as Any,
            "subscriptionsText": subscriptionsText as Any,
            "totalViews": totalViews as Any,
            "verified": verified as Any,
            "videos": videos.map(\.json.object)
        ]
    }

    static func from(_ json: JSON) -> Self {
        .init(
            app: VideosApp(rawValue: json["app"].stringValue) ?? .local,
            id: json["id"].stringValue,
            name: json["name"].stringValue,
            bannerURL: json["bannerURL"].url,
            thumbnailURL: json["thumbnailURL"].url,
            description: json["description"].stringValue,
            subscriptionsCount: json["subscriptionsCount"].int,
            subscriptionsText: json["subscriptionsText"].string,
            totalViews: json["totalViews"].int,
            videos: json["videos"].arrayValue.map { Video.from($0) }
        )
    }
}
