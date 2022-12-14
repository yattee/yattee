import Foundation

struct ContentItem: Identifiable {
    enum ContentType: String {
        case video, playlist, channel, placeholder

        private var sortOrder: Int {
            switch self {
            case .channel:
                return 1
            case .playlist:
                return 2
            default:
                return 3
            }
        }

        static func < (lhs: ContentType, rhs: ContentType) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }
    }

    static var placeholders: [Self] {
        (0 ..< 9).map { i in .init(id: String(i)) }
    }

    var video: Video!
    var playlist: ChannelPlaylist!
    var channel: Channel!

    var id: String = UUID().uuidString

    static func array(of videos: [Video]) -> [ContentItem] {
        videos.map { ContentItem(video: $0) }
    }

    static func array(of playlists: [ChannelPlaylist]) -> [ContentItem] {
        playlists.map { ContentItem(playlist: $0) }
    }

    static func array(of channels: [Channel]) -> [ContentItem] {
        channels.map { ContentItem(channel: $0) }
    }

    static func < (lhs: ContentItem, rhs: ContentItem) -> Bool {
        lhs.contentType < rhs.contentType
    }

    var contentType: ContentType {
        video.isNil ? (channel.isNil ? (playlist.isNil ? .placeholder : .playlist) : .channel) : .video
    }
}
