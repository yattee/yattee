import AVFoundation
import Defaults
import Foundation

// swiftlint:disable:next final_class
class Stream: Equatable, Hashable, Identifiable {
    enum Resolution: Comparable, Codable, Defaults.Serializable {
        case predefined(PredefinedResolution)
        case custom(height: Int, refreshRate: Int)

        enum PredefinedResolution: String, CaseIterable, Codable {
            // 8K UHD (16:9) Resolutions
            case hd4320p60, hd4320p30

            // 4K UHD (16:9) Resolutions
            case hd2160p60, hd2160p30

            // 1440p (16:9) Resolutions
            case hd1440p60, hd1440p30

            // 1080p (Full HD, 16:9) Resolutions
            case hd1080p60, hd1080p30

            // 720p (HD, 16:9) Resolutions
            case hd720p60, hd720p30

            // Standard Definition (SD) Resolutions
            case sd480p30
            case sd360p30
            case sd240p30
            case sd144p30
        }

        var name: String {
            switch self {
            case let .predefined(predefined):
                return predefined.rawValue
            case let .custom(height, refreshRate):
                return "\(height)p\(refreshRate != 30 ? ", \(refreshRate) fps" : "")"
            }
        }

        var height: Int {
            switch self {
            case let .predefined(predefined):
                return predefined.height
            case let .custom(height, _):
                return height
            }
        }

        var refreshRate: Int {
            switch self {
            case let .predefined(predefined):
                return predefined.refreshRate
            case let .custom(_, refreshRate):
                return refreshRate
            }
        }

        var bitrate: Int {
            switch self {
            case let .predefined(predefined):
                return predefined.bitrate
            case let .custom(height, refreshRate):
                // Find the closest predefined resolution based on height and refresh rate
                let closestPredefined = Stream.Resolution.PredefinedResolution.allCases.min {
                    abs($0.height - height) + abs($0.refreshRate - refreshRate) <
                        abs($1.height - height) + abs($1.refreshRate - refreshRate)
                }
                // Return the bitrate of the closest predefined resolution or a default bitrate if no close match is found
                return closestPredefined?.bitrate ?? 5_000_000
            }
        }

        static func from(resolution: String, fps: Int? = nil) -> Self {
            if let predefined = PredefinedResolution(rawValue: resolution) {
                return .predefined(predefined)
            }

            // Attempt to parse height and refresh rate
            if let height = Int(resolution.components(separatedBy: "p").first ?? ""), height > 0 {
                let refreshRate = fps ?? 30
                return .custom(height: height, refreshRate: refreshRate)
            }

            // Default behavior if parsing fails
            return .custom(height: 720, refreshRate: 30)
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.height == rhs.height ? (lhs.refreshRate < rhs.refreshRate) : (lhs.height < rhs.height)
        }

        enum CodingKeys: String, CodingKey {
            case predefined
            case custom
            case height
            case refreshRate
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let predefinedValue = try? container.decode(PredefinedResolution.self, forKey: .predefined) {
                self = .predefined(predefinedValue)
            } else if let height = try? container.decode(Int.self, forKey: .height),
                      let refreshRate = try? container.decode(Int.self, forKey: .refreshRate)
            {
                self = .custom(height: height, refreshRate: refreshRate)
            } else {
                // Set default resolution to 720p 30 if decoding fails
                self = .custom(height: 720, refreshRate: 30)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .predefined(predefinedValue):
                try container.encode(predefinedValue, forKey: .predefined)
            case let .custom(height, refreshRate):
                try container.encode(height, forKey: .height)
                try container.encode(refreshRate, forKey: .refreshRate)
            }
        }
    }

    enum Kind: String, Comparable {
        case hls, adaptive, stream

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

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }
    }

    enum Format: String {
        case avc1
        case mp4
        case av1
        case webm
        case hls
        case stream
        case unknown

        var description: String {
            switch self {
            case .webm:
                return "WebM"
            case .hls:
                return "adaptive (HLS)"
            case .stream:
                return "Stream"
            default:
                return rawValue.uppercased()
            }
        }

        static func from(_ string: String) -> Self {
            let lowercased = string.lowercased()

            if lowercased.contains("avc1") {
                return .avc1
            }
            if lowercased.contains("mpeg_4") || lowercased.contains("mp4") {
                return .mp4
            }
            if lowercased.contains("av01") {
                return .av1
            }
            if lowercased.contains("webm") {
                return .webm
            }
            if lowercased.contains("stream") {
                return .stream
            }
            if lowercased.contains("hls") {
                return .hls
            }
            return .unknown
        }
    }

    let id = UUID()

    var instance: Instance!
    var audioAsset: AVURLAsset!
    var videoAsset: AVURLAsset!
    var hlsURL: URL!
    var localURL: URL!

    var resolution: Resolution!
    var kind: Kind!
    var format: Format!

    var encoding: String?
    var videoFormat: String?
    var bitrate: Int?
    var requestRange: String?

    init(
        instance: Instance? = nil,
        audioAsset: AVURLAsset? = nil,
        videoAsset: AVURLAsset? = nil,
        hlsURL: URL? = nil,
        localURL: URL? = nil,
        resolution: Resolution? = nil,
        kind: Kind = .hls,
        encoding: String? = nil,
        videoFormat: String? = nil,
        bitrate: Int? = nil,
        requestRange: String? = nil
    ) {
        self.instance = instance
        self.audioAsset = audioAsset
        self.videoAsset = videoAsset
        self.hlsURL = hlsURL
        self.localURL = localURL
        self.resolution = resolution
        self.kind = kind
        self.encoding = encoding
        format = .from(videoFormat ?? "")
        self.bitrate = bitrate
        self.requestRange = requestRange
    }

    var isLocal: Bool {
        localURL != nil
    }

    var isHLS: Bool {
        hlsURL != nil
    }

    var quality: String {
        guard localURL.isNil else { return "Opened File" }

        if kind == .hls {
            return "adaptive (HLS)"
        }

        return resolution.name
    }

    var shortQuality: String {
        guard localURL.isNil else { return "File" }

        if kind == .hls {
            return "adaptive (HLS)"
        }

        if kind == .stream {
            return resolution.name
        }
        return resolutionAndFormat
    }

    var description: String {
        guard localURL.isNil else { return resolutionAndFormat }
        let instanceString = instance.isNil ? "" : " - (\(instance!.description))"
        return format != .hls ? "\(resolutionAndFormat)\(instanceString)" : "adaptive (HLS)\(instanceString)"
    }

    var resolutionAndFormat: String {
        let formatString = format == .unknown ? "" : " (\(format.description))"
        return "\(quality)\(formatString)"
    }

    var assets: [AVURLAsset] {
        [audioAsset, videoAsset]
    }

    var videoAssetContainsAudio: Bool {
        assets.dropFirst().allSatisfy { $0.url == assets.first!.url }
    }

    var singleAssetURL: URL? {
        guard localURL.isNil else {
            return URLBookmarkModel.shared.loadBookmark(localURL) ?? localURL
        }

        if kind == .hls {
            return hlsURL
        }
        if videoAssetContainsAudio {
            return videoAsset.url
        }

        return nil
    }

    static func == (lhs: Stream, rhs: Stream) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        if let url = videoAsset?.url {
            hasher.combine(url)
        }
        if let url = audioAsset?.url {
            hasher.combine(url)
        }
        if let url = hlsURL {
            hasher.combine(url)
        }
    }
}

extension Stream.Resolution.PredefinedResolution {
    var height: Int {
        switch self {
        // 8K UHD (16:9) Resolutions
        case .hd4320p60, .hd4320p30:
            return 4320

        // 4K UHD (16:9) Resolutions
        case .hd2160p60, .hd2160p30:
            return 2160

        // 1440p (16:9) Resolutions
        case .hd1440p60, .hd1440p30:
            return 1440

        // 1080p (Full HD, 16:9) Resolutions
        case .hd1080p60, .hd1080p30:
            return 1080

        // 720p (HD, 16:9) Resolutions
        case .hd720p60, .hd720p30:
            return 720

        // Standard Definition (SD) Resolutions
        case .sd480p30:
            return 480

        case .sd360p30:
            return 360

        case .sd240p30:
            return 240

        case .sd144p30:
            return 144
        }
    }

    var refreshRate: Int {
        switch self {
        // 60 fps Resolutions
        case .hd4320p60, .hd2160p60, .hd1440p60, .hd1080p60, .hd720p60:
            return 60

        // 30 fps Resolutions
        case .hd4320p30, .hd2160p30, .hd1440p30, .hd1080p30, .hd720p30,
             .sd480p30, .sd360p30, .sd240p30, .sd144p30:
            return 30
        }
    }

    // These values are an approximation.
    // https://support.google.com/youtube/answer/1722171?hl=en#zippy=%2Cbitrate

    var bitrate: Int {
        switch self {
        // 8K UHD (16:9) Resolutions
        case .hd4320p60:
            return 180_000_000 // Midpoint between 120 Mbps and 240 Mbps
        case .hd4320p30:
            return 120_000_000 // Midpoint between 80 Mbps and 160 Mbps
        // 4K UHD (16:9) Resolutions
        case .hd2160p60:
            return 60_500_000 // Midpoint between 53 Mbps and 68 Mbps
        case .hd2160p30:
            return 40_000_000 // Midpoint between 35 Mbps and 45 Mbps
        // 1440p (2K) Resolutions
        case .hd1440p60:
            return 24_000_000 // 24 Mbps
        case .hd1440p30:
            return 16_000_000 // 16 Mbps
        // 1080p (Full HD, 16:9) Resolutions
        case .hd1080p60:
            return 12_000_000 // 12 Mbps
        case .hd1080p30:
            return 8_000_000 // 8 Mbps
        // 720p (HD, 16:9) Resolutions
        case .hd720p60:
            return 7_500_000 // 7.5 Mbps
        case .hd720p30:
            return 5_000_000 // 5 Mbps
        // Standard Definition (SD) Resolutions
        case .sd480p30:
            return 2_500_000 // 2.5 Mbps
        case .sd360p30:
            return 1_000_000 // 1 Mbps
        case .sd240p30:
            return 1_000_000 // 1 Mbps
        case .sd144p30:
            return 600_000 // 0.6 Mbps
        }
    }
}
