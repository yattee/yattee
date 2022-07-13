import Foundation

extension Video {
    static var fixtureID: Video.ID = "video-fixture"
    static var fixtureChannelID: Channel.ID = "channel-fixture"

    static var fixture: Video {
        let thumbnailURL = "https://yt3.ggpht.com/ytc/AKedOLR-pT_JEsz_hcaA4Gjx8DHcqJ8mS42aTRqcVy6P7w=s88-c-k-c0x00ffffff-no-rj-mo"
        let chapterImageURL = URL(string: "https://pipedproxy.kavin.rocks/vi/rr2XfL_df3o/hqdefault_29633.jpg?sqp=-oaymwEcCNACELwBSFXyq4qpAw4IARUAAIhCGAFwAcABBg%3D%3D&rs=AOn4CLDFDm9D5SvsIA7D3v5n5KZahLs_UA&host=i.ytimg.com")!

        return Video(
            videoID: fixtureID,
            title: "Relaxing Piano Music to feel good",
            author: "Fancy Videotuber",
            length: 582,
            published: "7 years ago",
            views: 21534,
            description: "Some relaxing live piano music",
            genre: "Music",
            channel: Channel(
                id: fixtureChannelID,
                name: "The Channel",
                thumbnailURL: URL(string: thumbnailURL)!,
                subscriptionsCount: 2300,
                videos: []
            ),
            thumbnails: [],
            live: false,
            upcoming: false,
            publishedAt: Date(),
            likes: 37333,
            dislikes: 30,
            keywords: ["very", "cool", "video", "msfs 2020", "757", "747", "A380", "737-900", "MOD", "Zibo", "MD80", "MD11", "Rotate", "Laminar", "787", "A350", "MSFS", "MS2020", "Microsoft Flight Simulator", "Microsoft", "Flight", "Simulator", "SIM", "World", "Ortho", "Flying", "Boeing MAX"],
            chapters: [
                .init(title: "A good chapter name", image: chapterImageURL, start: 20),
                .init(title: "Other fine but incredibly too long chapter name, I don't know what else to say", image: chapterImageURL, start: 30),
                .init(title: "Short", image: chapterImageURL, start: 60)
            ]
        )
    }

    static var fixtureLiveWithoutPublishedOrViews: Video {
        var video = fixture

        video.title = "\(video.title) \(video.title) \(video.title) \(video.title) \(video.title)"
        video.published = "0 seconds ago"
        video.views = 0
        video.live = true

        return video
    }

    static var fixtureUpcomingWithoutPublishedOrViews: Video {
        var video = fixtureLiveWithoutPublishedOrViews

        video.live = false
        video.upcoming = true

        return video
    }

    static var allFixtures: [Video] {
        [fixture, fixtureLiveWithoutPublishedOrViews, fixtureUpcomingWithoutPublishedOrViews]
    }

    static func fixtures(_ count: Int) -> [Video] {
        var result = [Video]()
        while result.count < count {
            result.append(allFixtures.shuffled().first!)
        }

        return result
    }
}
