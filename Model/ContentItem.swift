import Foundation

struct ContentItem: Identifiable {
    enum ContentType: String {
        case video, playlist, channel

        private var sortOrder: Int {
            switch self {
            case .channel:
                return 1
            case .video:
                return 2
            default:
                return 3
            }
        }

        static func < (lhs: ContentType, rhs: ContentType) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }
    }

    var video: Video!
    var playlist: Playlist!
    var channel: Channel!

    static func array(of videos: [Video]) -> [ContentItem] {
        videos.map { ContentItem(video: $0) }
    }

    static func < (lhs: ContentItem, rhs: ContentItem) -> Bool {
        lhs.contentType < rhs.contentType
    }

    var id: String {
        "\(contentType.rawValue)-\(video?.id ?? playlist?.id ?? channel?.id ?? "")"
    }

    var contentType: ContentType {
        if !playlist.isNil {
            return .playlist
        } else if !channel.isNil {
            return .channel
        }

        return .video
    }
}
