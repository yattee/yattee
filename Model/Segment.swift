import CoreMedia
import Foundation
import SwiftyJSON

// swiftlint:disable:next final_class
class Segment: ObservableObject, Hashable {
    let category: String
    let segment: [Double]
    let uuid: String
    let videoDuration: Int

    var start: Double {
        segment.first!
    }

    var end: Double {
        segment.last!
    }

    var duration: Double {
        end - start
    }

    var endTime: CMTime {
        .secondsInDefaultTimescale(end)
    }

    init(category: String, segment: [Double], uuid: String, videoDuration: Int) {
        self.category = category
        self.segment = segment
        self.uuid = uuid
        self.videoDuration = videoDuration
    }

    func timeInSegment(_ time: CMTime) -> Bool {
        (start ... end).contains(time.seconds)
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
