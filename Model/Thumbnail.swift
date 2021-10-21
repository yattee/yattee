import Foundation
import SwiftyJSON

struct Thumbnail {
    enum Quality: String, CaseIterable {
        case maxres, maxresdefault, sddefault, high, medium, `default`, start, middle, end

        var filename: String {
            switch self {
            case .maxres:
                return "maxres"
            case .maxresdefault:
                return "maxresdefault"
            case .sddefault:
                return "sddefault"
            case .high:
                return "hqdefault"
            case .medium:
                return "mqdefault"
            case .default:
                return "default"
            case .start:
                return "1"
            case .middle:
                return "2"
            case .end:
                return "3"
            }
        }
    }

    var url: URL
    var quality: Quality

    init(url: URL, quality: Quality) {
        self.url = url
        self.quality = quality
    }
}
