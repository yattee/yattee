import Foundation

struct ChannelPlaylist: Identifiable {
    var id: String = UUID().uuidString
    var title: String
    var thumbnailURL: URL?
    var channel: Channel?
    var videos = [Video]()
    var videosCount: Int?
}
