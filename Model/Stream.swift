import AVFoundation
import Defaults
import Foundation

// swiftlint:disable:next final_class
class Stream: Equatable, Hashable, Identifiable {
    enum Resolution: String, CaseIterable, Comparable, Defaults.Serializable {
        case hd2160p60
        case hd2160p
        case hd1440p60
        case hd1440p
        case hd1080p60
        case hd1080p
        case hd720p60
        case hd720p
        case sd480p
        case sd360p
        case sd240p
        case sd144p
        case unknown

        var name: String {
            "\(height)p\(refreshRate != -1 ? ", \(refreshRate) fps" : "")"
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
            return Int(refreshRatePart.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? -1
        }

        static func from(resolution: String) -> Resolution {
            allCases.first { "\($0)".contains(resolution) } ?? .unknown
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

    let id = UUID()

    var instance: Instance!
    var audioAsset: AVURLAsset!
    var videoAsset: AVURLAsset!
    var hlsURL: URL!

    var resolution: Resolution!
    var kind: Kind!

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
        self.videoFormat = videoFormat
    }

    var quality: String {
        if resolution == .hd2160p {
            return "4K (2160p)"
        }

        return kind == .hls ? "adaptive (HLS)" : "\(resolution.name)\(kind == .stream ? " (\(kind.rawValue))" : "")"
    }

    var format: String {
        let lowercasedFormat = (videoFormat ?? "unknown").lowercased()
        if lowercasedFormat.contains("webm") {
            return "WEBM"
        } else if lowercasedFormat.contains("avc1") {
            return "avc1"
        } else if lowercasedFormat.contains("av01") {
            return "AV1"
        } else if lowercasedFormat.contains("mpeg_4") || lowercasedFormat.contains("mp4") {
            return "MP4"
        } else {
            return lowercasedFormat
        }
    }

    var description: String {
        let formatString = format == "unknown" ? "" : " (\(format))"
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
