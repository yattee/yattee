import CoreMedia
import Foundation

extension CMTime {
    static let defaultTimescale: CMTimeScale = 1_000_000

    static func secondsInDefaultTimescale(_ seconds: TimeInterval) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: CMTime.defaultTimescale)
    }
}
