import Foundation

extension Thumbnail {
    static func fixture(videoId: String, quality: Thumbnail.Quality = .maxres) -> Thumbnail {
        Thumbnail(url: fixtureUrl(videoId: videoId, quality: quality), quality: quality)
    }

    static func fixturesForAllQualities(videoId: String) -> [Thumbnail] {
        Thumbnail.Quality.allCases.map { fixture(videoId: videoId, quality: $0) }
    }

    private static var fixturesHost: String {
        "https://invidious.home.arekf.net"
    }

    private static func fixtureUrl(videoId: String, quality: Thumbnail.Quality) -> URL {
        URL(string: "\(fixturesHost)/vi/\(videoId)/\(quality.filename).jpg")!
    }
}
