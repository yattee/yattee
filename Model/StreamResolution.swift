import Foundation

enum StreamResolution: String, CaseIterable, Comparable {
    case hd1080p, hd720p, sd480p, sd360p, sd240p, sd144p

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
