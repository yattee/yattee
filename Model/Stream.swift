import AVFoundation
import Defaults
import Foundation

// swiftlint:disable:next final_class
class Stream: Equatable, Hashable, Identifiable {
    enum Resolution: String, CaseIterable, Comparable, Defaults.Serializable {
        case hd2160p60
        case hd2160p50
        case hd2160p48
        case hd2160p30
        case hd1440p60
        case hd1440p50
        case hd1440p48
        case hd1440p30
        case hd1080p60
        case hd1080p50
        case hd1080p48
        case hd1080p30
        case hd720p60
        case hd720p50
        case hd720p48
        case hd720p30
        case sd480p30
        case sd360p30
        case sd240p30
        case sd144p30
        case unknown

        var name: String {
            "\(height)p\(refreshRate != -1 && refreshRate != 30 ? ", \(refreshRate) fps" : "")"
        }

        var height: Int {
            if self == .unknown {
                return -1
            }

            let resolutionPart = rawValue.components(separatedBy: "p").first!
            return Int(resolutionPart.components(separatedBy: CharacterSet.decimalDigits.inverted).joined())!
        }

        var refreshRate: Int {
            if self == .unknown {
                return -1
            }

            let refreshRatePart = rawValue.components(separatedBy: "p")[1]

            if refreshRatePart.isEmpty {
                return 30
            }

            return Int(refreshRatePart.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? -1
        }

        static func from(resolution: String, fps: Int? = nil) -> Resolution {
            allCases.first { $0.rawValue.contains(resolution) && $0.refreshRate == (fps ?? 30) } ?? .unknown
        }

        static func < (lhs: Resolution, rhs: Resolution) -> Bool {
            lhs.height < rhs.height
        }
    }

    enum Kind: String, Comparable {
        case stream, adaptive, hls

        private var sortOrder: Int {
            switch self {
            case .hls:
                return 0
            case .stream:
                return 1
            case .adaptive:
                return 2
            }
        }

        static func < (lhs: Kind, rhs: Kind) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }
    }

    enum Format: String, Comparable {
        case webm
        case avc1
        case av1
        case mp4
        case unknown

        private var sortOrder: Int {
            switch self {
            case .webm:
                return 0
            case .mp4:
                return 1
            case .avc1:
                return 2
            case .av1:
                return 3
            case .unknown:
                return 4
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }

        static func from(_ string: String) -> Self {
            let lowercased = string.lowercased()

            if lowercased.contains("webm") {
                return .webm
            } else if lowercased.contains("avc1") {
                return .avc1
            } else if lowercased.contains("av01") {
                return .av1
            } else if lowercased.contains("mpeg_4") || lowercased.contains("mp4") {
                return .mp4
            } else {
                return .unknown
            }
        }
    }

    let id = UUID()

    var instance: Instance!
    var audioAsset: AVURLAsset!
    var videoAsset: AVURLAsset!
    var hlsURL: URL!

    var resolution: Resolution!
    var kind: Kind!
    var format: Format!

    var encoding: String!
    var videoFormat: String!

    init(
        instance: Instance? = nil,
        audioAsset: AVURLAsset? = nil,
        videoAsset: AVURLAsset? = nil,
        hlsURL: URL? = nil,
        resolution: Resolution? = nil,
        kind: Kind = .hls,
        encoding: String? = nil,
        videoFormat: String? = nil
    ) {
        self.instance = instance
        self.audioAsset = audioAsset
        self.videoAsset = videoAsset
        self.hlsURL = hlsURL
        self.resolution = resolution
        self.kind = kind
        self.encoding = encoding
        format = .from(videoFormat ?? "")
    }

    var quality: String {
        if resolution == .hd2160p30 {
            return "4K (2160p)"
        }

        return kind == .hls ? "adaptive (HLS)" : "\(resolution.name)\(kind == .stream ? " (\(kind.rawValue))" : "")"
    }

    var shortQuality: String {
        if resolution?.height == 2160 {
            return "4K"
        } else if kind == .hls {
            return "HLS"
        } else {
            return resolution?.name ?? "?"
        }
    }

    var description: String {
        let formatString = format == .unknown ? "" : " (\(format.rawValue))"
        return "\(quality)\(formatString) - \(instance?.description ?? "")"
    }

    var assets: [AVURLAsset] {
        [audioAsset, videoAsset]
    }

    var videoAssetContainsAudio: Bool {
        assets.dropFirst().allSatisfy { $0.url == assets.first!.url }
    }

    var singleAssetURL: URL? {
        if kind == .hls {
            return hlsURL
        } else if videoAssetContainsAudio {
            return videoAsset.url
        }

        return nil
    }

    static func == (lhs: Stream, rhs: Stream) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(videoAsset?.url)
        hasher.combine(audioAsset?.url)
        hasher.combine(hlsURL)
    }
}
