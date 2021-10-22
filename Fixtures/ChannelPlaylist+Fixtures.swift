import Foundation

extension ChannelPlaylist {
    static var fixture: ChannelPlaylist {
        ChannelPlaylist(
            title: "Playlist with a very long title that will not fit easily in the screen",
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/hT_nvWreIhg/hqdefault.jpg?sqp=-oaymwEWCKgBEF5IWvKriqkDCQgBFQAAiEIYAQ==&rs=AOn4CLAAD21_-Bo6Td1z3cV-UFyoi1flEg")!,
            channel: Video.fixture.channel,
            videos: Video.allFixtures
        )
    }
}
