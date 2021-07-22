import AVFoundation
import Foundation

// swiftlint:disable:next final_class
class Stream: Equatable, Hashable {
    enum Resolution: String, CaseIterable, Comparable {
        case hd1080p, hd720p, sd480p, sd360p, sd240p, sd144p

        var height: Int {
            Int(rawValue.components(separatedBy: CharacterSet.decimalDigits.inverted).joined())!
        }

        static func from(resolution: String) -> Resolution? {
            allCases.first { "\($0)".contains(resolution) }
        }

        static func < (lhs: Resolution, rhs: Resolution) -> Bool {
            lhs.height < rhs.height
        }
    }

    enum Kind: String, Comparable {
        case stream, adaptive

        private var sortOrder: Int {
            switch self {
            case .stream:
                return 0
            case .adaptive:
                return 1
            }
        }

        static func < (lhs: Kind, rhs: Kind) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }
    }

    var audioAsset: AVURLAsset
    var videoAsset: AVURLAsset

    var resolution: Resolution
    var kind: Kind

    var encoding: String

    init(audioAsset: AVURLAsset, videoAsset: AVURLAsset, resolution: Resolution, kind: Kind, encoding: String) {
        self.audioAsset = audioAsset
        self.videoAsset = videoAsset
        self.resolution = resolution
        self.kind = kind
        self.encoding = encoding
    }

    var description: String {
        "\(resolution.height)p"
    }

    var assets: [AVURLAsset] {
        [audioAsset, videoAsset]
    }

    var oneMeaningfullAsset: Bool {
        assets.dropFirst().allSatisfy { $0 == assets.first }
    }

    var assetsLoaded: Bool {
        assets.allSatisfy { $0.statusOfValue(forKey: "playable", error: nil) == .loaded }
    }

    var loadedAssets: [AVURLAsset] {
        assets.filter { $0.statusOfValue(forKey: "playable", error: nil) == .loaded }
    }

    func cancelLoadingAssets() {
        assets.forEach { $0.cancelLoading() }
    }

    static func == (lhs: Stream, rhs: Stream) -> Bool {
        lhs.resolution == rhs.resolution && lhs.kind == rhs.kind
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(videoAsset.url)
    }
}
