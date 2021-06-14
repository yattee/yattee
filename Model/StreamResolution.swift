import Foundation

enum StreamResolution: String, CaseIterable, Comparable {
    case hd_1080p, hd_720p, sd_480p, sd_360p, sd_240p, sd_144p

    var height: Int {
        Int(rawValue.components(separatedBy: CharacterSet.decimalDigits.inverted).joined())!
    }

    static func from(resolution: String) -> StreamResolution? {
        allCases.first { "\($0)".contains(resolution) }
    }

    static func < (lhs: StreamResolution, rhs: StreamResolution) -> Bool {
        lhs.height < rhs.height
    }
}
