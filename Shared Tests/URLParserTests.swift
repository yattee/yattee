import XCTest

final class URLParserTests: XCTestCase {
    private static let videos: [String: String] = [
        "https://www.youtube.com/watch?v=_E0PWQvW-14&list=WL&index=4&t=155s": "_E0PWQvW-14",
        "https://youtu.be/IRsc57nK8mg?t=20": "IRsc57nK8mg",
        "https://www.youtube-nocookie.com/watch?index=4&v=cE1PSQrWc11&list=WL&t=155s": "cE1PSQrWc11",
        "https://invidious.snopyta.org/watch?v=XpowfENlJAw": "XpowfENlJAw",
        "/watch?v=VQ_f5RymW70": "VQ_f5RymW70",
        "watch?v=IUTGFQpKaPU&t=30s": "IUTGFQpKaPU"
    ]

    private static let channelsByName: [String: String] = [
        "https://www.youtube.com/c/tennistv": "tennistv",
        "youtube.com/c/MKBHD": "MKBHD",
        "c/ABCDE": "ABCDE"
    ]

    private static let channelsByID: [String: String] = [
        "https://piped.kavin.rocks/channel/UCbcxFkd6B9xUU54InHv4Tig": "UCbcxFkd6B9xUU54InHv4Tig",
        "youtube.com/channel/UCbcxFkd6B9xUU54InHv4Tig": "UCbcxFkd6B9xUU54InHv4Tig",
        "channel/ABCDE": "ABCDE"
    ]

    private static let playlists: [String: String] = [
        "https://www.youtube.com/playlist?list=PLDIoUOhQQPlXr63I_vwF9GD8sAKh77dWU": "PLDIoUOhQQPlXr63I_vwF9GD8sAKh77dWU",
        "https://www.youtube.com/watch?v=playlist&list=PLDIoUOhQQPlXr63I_vwF9GD8sAKh77dWU": "PLDIoUOhQQPlXr63I_vwF9GD8sAKh77dWU",
        "youtube.com/watch?v=playlist&list=PLDIoUOhQQPlXr63I_vwF9GD8sAKh77dWU": "PLDIoUOhQQPlXr63I_vwF9GD8sAKh77dWU",
        "/watch?v=playlist&list=PLDIoUOhQQPlXr63I_vwF9GD8sAKh77dWU": "PLDIoUOhQQPlXr63I_vwF9GD8sAKh77dWU",
        "watch?v=playlist&list=PLDIoUOhQQPlXr63I_vwF9GD8sAKh77dWU": "PLDIoUOhQQPlXr63I_vwF9GD8sAKh77dWU",
        "playlist?list=ABCDE": "ABCDE"
    ]

    private static let searches: [String: String] = [
        "https://www.youtube.com/results?search_query=my+query+text": "my query text",
        "https://piped.kavin.rocks/results?search_query=query+text": "query text",
        "https://www.youtube.com/results?search_query=my+query+text&sp=EgIQAg%253D%253D": "my query text",
        "https://www.youtube.com/results?search_query=encoded+%22query+text%22+@%23%252": "encoded \"query text\" @#%2",
        "https://www.youtube.com/results?search_query=a%2Bb%3Dc": "a b=c",
        "www.youtube.com/results?search_query=my+query+text&sp=EgIQAg%253D%253D": "my query text",
        "/results?search_query=a+b%3Dcde": "a b=cde",
        "search?search_query=a+b%3Dcde": "a b=cde"
    ]

    func testVideosParsing() throws {
        Self.videos.forEach { url, id in
            let parser = URLParser(url: URL(string: url)!)
            XCTAssertEqual(parser.destination, .video)
            XCTAssertEqual(parser.videoID, id)
        }
    }

    func testChannelsByNameParsing() throws {
        Self.channelsByName.forEach { url, name in
            let parser = URLParser(url: URL(string: url)!)
            XCTAssertEqual(parser.destination, .channel)
            XCTAssertEqual(parser.channelName, name)
        }
    }

    func testChannelsByIdParsing() throws {
        Self.channelsByID.forEach { url, id in
            let parser = URLParser(url: URL(string: url)!)
            XCTAssertEqual(parser.destination, .channel)
            XCTAssertEqual(parser.channelID, id)
        }
    }

    func testPlaylistsParsing() throws {
        Self.playlists.forEach { url, id in
            let parser = URLParser(url: URL(string: url)!)
            XCTAssertEqual(parser.destination, .playlist)
            XCTAssertEqual(parser.playlistID, id)
        }
    }

    func testSearchesParsing() throws {
        Self.searches.forEach { url, query in
            let parser = URLParser(url: URL(string: url)!)
            XCTAssertEqual(parser.destination, .search)
            XCTAssertEqual(parser.searchQuery, query)
        }
    }

    func testTimeParsing() throws {
        let samples: [String: Int?] = [
            "https://www.youtube.com/watch?v=_E0PWQvW-14&list=WL&index=4&t=155s": 155,
            "https://youtu.be/IRsc57nK8mg?t=20m10s": 1210,
            "https://youtu.be/IRsc57nK8mg?t=3x4z": nil,
            "https://www.youtube-nocookie.com/watch?index=4&v=cE1PSQrWc11&list=WL&t=2H3m5s": 7385,
            "https://youtu.be/VQ_f5RymW70?t=378": 378,
            "watch?v=IUTGFQpKaPU&t=30s": 30
        ]

        samples.forEach { url, time in
            XCTAssertEqual(
                URLParser(url: URL(string: url)!).time,
                time
            )
        }
    }
}
