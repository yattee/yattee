import AVFoundation
import Defaults
import Foundation

// swiftlint:disable:next final_class
class Stream: Equatable, Hashable, Identifiable {
    enum ResolutionSetting: String, Defaults.Serializable, CaseIterable {
        case hd720pFirstThenBest, hd1080p, hd720p, sd480p, sd360p, sd240p, sd144p

        var value: Stream.Resolution {
            switch self {
            case .hd720pFirstThenBest:
                return .hd720p
            default:
                return Stream.Resolution(rawValue: rawValue)!
            }
        }

        var description: String {
            switch self {
            case .hd720pFirstThenBest:
                return "Default: adaptive"
            default:
                return value.name
            }
        }
    }

    enum Resolution: String, CaseIterable, Comparable, Defaults.Serializable {
        case hd1440p60, hd1440p, hd1080p60, hd1080p, hd720p60, hd720p, sd480p, sd360p, sd240p, sd144p, unknown

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

    init(
        instance: Instance? = nil,
        audioAsset: AVURLAsset? = nil,
        videoAsset: AVURLAsset? = nil,
        hlsURL: URL? = nil,
        resolution: Resolution? = nil,
        kind: Kind = .hls,
        encoding: String? = nil
    ) {
        self.instance = instance
        self.audioAsset = audioAsset
        self.videoAsset = videoAsset
        self.hlsURL = hlsURL
        self.resolution = resolution
        self.kind = kind
        self.encoding = encoding
    }

    var shortQuality: String {
        kind == .hls ? "adaptive" : resolution.name
    }

    var quality: String {
        kind == .hls ? "adaptive (HLS)" : "\(resolution.name) \(kind == .stream ? "(\(kind.rawValue))" : "")"
    }

    var description: String {
        "\(quality) - \(instance?.description ?? "")"
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

    func withAssetsFrom(_ instance: Instance) -> Stream {
        if kind == .hls {
            return Stream(instance: instance, hlsURL: hlsURL)
        } else {
            return Stream(
                instance: instance,
                audioAsset: AVURLAsset(url: assetURLFrom(instance: instance, url: (audioAsset ?? videoAsset).url)!),
                videoAsset: AVURLAsset(url: assetURLFrom(instance: instance, url: videoAsset.url)!),
                resolution: resolution,
                kind: kind,
                encoding: encoding
            )
        }
    }

    private func assetURLFrom(instance: Instance, url: URL) -> URL? {
        guard let instanceURLComponents = URLComponents(string: instance.url),
              var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        urlComponents.scheme = instanceURLComponents.scheme
        urlComponents.host = instanceURLComponents.host

        return urlComponents.url
    }
}
