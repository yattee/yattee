import XCTest

final class VideoURLParserTests: XCTestCase {
    func testIDParsing() throws {
        let samples: [String: String] = [
            "https://www.youtube.com/watch?v=_E0PWQvW-14&list=WL&index=4&t=155s": "_E0PWQvW-14",
            "https://youtu.be/IRsc57nK8mg?t=20": "IRsc57nK8mg",
            "https://www.youtube-nocookie.com/watch?index=4&v=cE1PSQrWc11&list=WL&t=155s": "cE1PSQrWc11",
            "https://invidious.snopyta.org/watch?v=XpowfENlJAw" : "XpowfENlJAw",
            "/watch?v=VQ_f5RymW70" : "VQ_f5RymW70",
            "watch?v=IUTGFQpKaPU&t=30s": "IUTGFQpKaPU"
        ]

        samples.forEach { url, id in
            XCTAssertEqual(
                VideoURLParser(url: URL(string: url)!).id,
                id
            )
        }
    }

    func testTimeParsing() throws {
        let samples: [String: TimeInterval?] = [
            "https://www.youtube.com/watch?v=_E0PWQvW-14&list=WL&index=4&t=155s": 155,
            "https://youtu.be/IRsc57nK8mg?t=20m10s": 1210,
            "https://youtu.be/IRsc57nK8mg?t=3x4z": nil,
            "https://www.youtube-nocookie.com/watch?index=4&v=cE1PSQrWc11&list=WL&t=2H3m5s": 7385,
            "https://youtu.be/VQ_f5RymW70?t=378": 378,
            "watch?v=IUTGFQpKaPU&t=30s": 30
        ]

        samples.forEach { url, time in
            XCTAssertEqual(
                VideoURLParser(url: URL(string: url)!).time,
                time
            )
        }
    }
}
