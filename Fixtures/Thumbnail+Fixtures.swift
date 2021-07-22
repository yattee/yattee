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
        URL(string: "\(fixturesHost)/vi/\(videoId)/\(filenameForQuality(quality)).jpg")!
    }

    private static func filenameForQuality(_ quality: Thumbnail.Quality) -> String {
        switch quality {
        case .high:
            return "hqdefault"
        case .medium:
            return "mqdefault"
        case .start:
            return "1"
        case .middle:
            return "2"
        case .end:
            return "3"
        default:
            return quality.rawValue
        }
    }
}
