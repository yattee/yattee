import XCTest

final class InstancesModelTests: XCTestCase {
    func testStandardizedURL() throws {
        let samples: [String: String] = [
            "https://www.youtube.com/": "https://www.youtube.com",
            "https://www.youtube.com": "https://www.youtube.com",
        ]

        samples.forEach { url, standardized in
            XCTAssertEqual(
                InstancesModel.standardizedURL(url),
                standardized
            )
        }
    }
}
