import AVFoundation
import Defaults
import Foundation
import SwiftyJSON

struct Channel: Identifiable, Hashable {
    enum ContentType: String, Identifiable {
        case videos
        case playlists
        case livestreams
        case shorts
        case channels

        var id: String {
            rawValue
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
    }

    struct Tab: Identifiable, Hashable {
        var contentType: ContentType
        var data: String

        var id: String {
            contentType.id
        }
    }

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
        if subscriptionsCount != nil, subscriptionsCount! > 0 {
            return subscriptionsCount!.formattedAsAbbreviation()
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
}
