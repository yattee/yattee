extension Video {
    static var fixture: Video {
        let id = "D2sxamzaHkM"

        return Video(
            id: id,
            title: "Relaxing Piano Music",
            author: "Fancy Videotuber",
            length: 582,
            published: "7 years ago",
            views: 1024,
            channelID: "AbCdEFgHI",
            description: "Some relaxing live piano music",
            genre: "Music",
            thumbnails: Thumbnail.fixturesForAllQualities(videoId: id),
            live: false,
            upcoming: false
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
}
