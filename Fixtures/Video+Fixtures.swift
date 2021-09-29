import Foundation

extension Video {
    static var fixture: Video {
        let id = "D2sxamzaHkM"

        return Video(
            id: UUID().uuidString,
            title: "Relaxing Piano Music that will make you feel amazingly good",
            author: "Fancy Videotuber",
            length: 582,
            published: "7 years ago",
            views: 21534,
            description: "Some relaxing live piano music",
            genre: "Music",
            channel: Channel(id: "AbCdEFgHI", name: "The Channel", subscriptionsCount: 2300, videos: []),
            thumbnails: Thumbnail.fixturesForAllQualities(videoId: id),
            live: false,
            upcoming: false,
            publishedAt: Date.now,
            likes: 37333,
            dislikes: 30,
            keywords: ["very", "cool", "video", "msfs 2020", "757", "747", "A380", "737-900", "MOD", "Zibo", "MD80", "MD11", "Rotate", "Laminar", "787", "A350", "MSFS", "MS2020", "Microsoft Flight Simulator", "Microsoft", "Flight", "Simulator", "SIM", "World", "Ortho", "Flying", "Boeing MAX"]
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
