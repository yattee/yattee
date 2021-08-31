import XCTest

final class IntFormatTests: XCTestCase {
    func testFormattedAsAbbreviation() throws {
        let samples: [Int: String] = [
            1: "1",
            999: "999",
            1000: "1K",
            1101: "1,1K",
            12345: "12,3K",
            123_456: "123,5K",
            123_626_789: "123,6M"
        ]

        samples.forEach { value, formatted in
            XCTAssertEqual(value.formattedAsAbbreviation(), formatted)
        }
    }
}
