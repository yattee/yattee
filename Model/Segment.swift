import CoreMedia
import Foundation
import SwiftyJSON

// swiftlint:disable:next final_class
class Segment: ObservableObject, Hashable {
    let category: String
    let segment: [Double]
    let uuid: String
    let videoDuration: Int

    init(category: String, segment: [Double], uuid: String, videoDuration: Int) {
        self.category = category
        self.segment = segment
        self.uuid = uuid
        self.videoDuration = videoDuration
    }

    func timeInSegment(_ time: CMTime) -> Bool {
        (segment.first! ... segment.last!).contains(time.seconds)
    }

    var skipTo: CMTime {
        CMTime(seconds: segment.last!, preferredTimescale: 1)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }

    static func == (lhs: Segment, rhs: Segment) -> Bool {
        lhs.uuid == rhs.uuid
    }

    func title() -> String {
        category
    }
}
