import AVFoundation
import Defaults
import Foundation

// swiftlint:disable:next final_class
class Stream: Equatable, Hashable, Identifiable {
    enum Resolution: String, CaseIterable, Comparable, Defaults.Serializable {
        // Some 16:19 and 16:10 resolutions are also used in 2:1 videos

        // 8K UHD (16:9) Resolutions
        case hd4320p60
        case hd4320p50
        case hd4320p48
        case hd4320p30
        case hd4320p25
        case hd4320p24

        // 5K (16:9) Resolutions
        case hd2560p60
        case hd2560p50
        case hd2560p48
        case hd2560p30
        case hd2560p25
        case hd2560p24

        // 2:1 Aspect Ratio (Univisium) Resolutions
        case hd2880p60
        case hd2880p50
        case hd2880p48
        case hd2880p30
        case hd2880p25
        case hd2880p24

        // 16:10 Resolutions
        case hd2400p60
        case hd2400p50
        case hd2400p48
        case hd2400p30
        case hd2400p25
        case hd2400p24

        // 16:9 Resolutions
        case hd2160p60
        case hd2160p50
        case hd2160p48
        case hd2160p30
        case hd2160p25
        case hd2160p24

        // 16:10 Resolutions
        case hd1600p60
        case hd1600p50
        case hd1600p48
        case hd1600p30
        case hd1600p25
        case hd1600p24

        // 16:9 Resolutions
        case hd1440p60
        case hd1440p50
        case hd1440p48
        case hd1440p30
        case hd1440p25
        case hd1440p24

        // 16:10 Resolutions
        case hd1280p60
        case hd1280p50
        case hd1280p48
        case hd1280p30
        case hd1280p25
        case hd1280p24

        // 16:10 Resolutions
        case hd1200p60
        case hd1200p50
        case hd1200p48
        case hd1200p30
        case hd1200p25
        case hd1200p24

        // 16:9 Resolutions
        case hd1080p60
        case hd1080p50
        case hd1080p48
        case hd1080p30
        case hd1080p25
        case hd1080p24

        // 16:10 Resolutions
        case hd1050p60
        case hd1050p50
        case hd1050p48
        case hd1050p30
        case hd1050p25
        case hd1050p24

        // 16:9 Resolutions
        case hd960p60
        case hd960p50
        case hd960p48
        case hd960p30
        case hd960p25
        case hd960p24

        // 16:10 Resolutions
        case hd900p60
        case hd900p50
        case hd900p48
        case hd900p30
        case hd900p25
        case hd900p24

        // 16:10 Resolutions
        case hd800p60
        case hd800p50
        case hd800p48
        case hd800p30
        case hd800p25
        case hd800p24

        // 16:9 Resolutions
        case hd720p60
        case hd720p50
        case hd720p48
        case hd720p30
        case hd720p25
        case hd720p24

        // Standard Definition (SD) Resolutions
        case sd854p30
        case sd854p25
        case sd768p30
        case sd768p25
        case sd640p30
        case sd640p25
        case sd480p30
        case sd480p25

        case sd428p30
        case sd428p25
        case sd360p30
        case sd360p25
        case sd320p30
        case sd320p25
        case sd240p30
        case sd240p25
        case sd214p30
        case sd214p25
        case sd144p30
        case sd144p25
        case sd128p30
        case sd128p25

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

        // These values are an approximation.
        // https://support.google.com/youtube/answer/1722171?hl=en#zippy=%2Cbitrate

        var bitrate: Int {
            switch self {
            // 8K UHD (16:9) Resolutions
            case .hd4320p60, .hd4320p50, .hd4320p48, .hd4320p30, .hd4320p25, .hd4320p24:
                return 85_000_000 // 85 Mbit/s

            // 5K (16:9) Resolutions
            case .hd2880p60, .hd2880p50, .hd2880p48, .hd2880p30, .hd2880p25, .hd2880p24:
                return 45_000_000 // 45 Mbit/s

            // 2:1 Aspect Ratio (Univisium) Resolutions
            case .hd2560p60, .hd2560p50, .hd2560p48, .hd2560p30, .hd2560p25, .hd2560p24:
                return 30_000_000 // 30 Mbit/s

            // 16:10 Resolutions
            case .hd2400p60, .hd2400p50, .hd2400p48, .hd2400p30, .hd2400p25, .hd2400p24:
                return 35_000_000 // 35 Mbit/s

            // 4K UHD (16:9) Resolutions
            case .hd2160p60, .hd2160p50, .hd2160p48, .hd2160p30, .hd2160p25, .hd2160p24:
                return 56_000_000 // 56 Mbit/s

            // 16:10 Resolutions
            case .hd1600p60, .hd1600p50, .hd1600p48, .hd1600p30, .hd1600p25, .hd1600p24:
                return 20_000_000 // 20 Mbit/s

            // 1440p (16:9) Resolutions
            case .hd1440p60, .hd1440p50, .hd1440p48, .hd1440p30, .hd1440p25, .hd1440p24:
                return 24_000_000 // 24 Mbit/s

            // 1280p (16:10) Resolutions
            case .hd1280p60, .hd1280p50, .hd1280p48, .hd1280p30, .hd1280p25, .hd1280p24:
                return 15_000_000 // 15 Mbit/s

            // 1200p (16:10) Resolutions
            case .hd1200p60, .hd1200p50, .hd1200p48, .hd1200p30, .hd1200p25, .hd1200p24:
                return 18_000_000 // 18 Mbit/s

            // 1080p (16:9) Resolutions
            case .hd1080p60, .hd1080p50, .hd1080p48, .hd1080p30, .hd1080p25, .hd1080p24:
                return 12_000_000 // 12 Mbit/s

            // 1050p (16:10) Resolutions
            case .hd1050p60, .hd1050p50, .hd1050p48, .hd1050p30, .hd1050p25, .hd1050p24:
                return 10_000_000 // 10 Mbit/s

            // 960p Resolutions
            case .hd960p60, .hd960p50, .hd960p48, .hd960p30, .hd960p25, .hd960p24:
                return 8_000_000 // 8 Mbit/s

            // 900p (16:10) Resolutions
            case .hd900p60, .hd900p50, .hd900p48, .hd900p30, .hd900p25, .hd900p24:
                return 7_000_000 // 7 Mbit/s

            // 800p (16:10) Resolutions
            case .hd800p60, .hd800p50, .hd800p48, .hd800p30, .hd800p25, .hd800p24:
                return 6_000_000 // 6 Mbit/s

            // 720p (16:9) Resolutions
            case .hd720p60, .hd720p50, .hd720p48, .hd720p30, .hd720p25, .hd720p24:
                return 9_500_000 // 9.5 Mbit/s

            // Standard Definition (SD) Resolutions
            case .sd854p30, .sd854p25, .sd768p30, .sd768p25, .sd640p30, .sd640p25:
                return 4_000_000 // 4 Mbit/s

            case .sd480p30, .sd480p25:
                return 2_500_000 // 2.5 Mbit/s

            case .sd428p30, .sd428p25:
                return 2_000_000 // 2 Mbit/s

            case .sd360p30, .sd360p25:
                return 1_500_000 // 1.5 Mbit/s

            case .sd320p30, .sd320p25:
                return 1_200_000 // 1.2 Mbit/s

            case .sd240p30, .sd240p25:
                return 1_000_000 // 1 Mbit/s

            case .sd214p30, .sd214p25:
                return 800_000 // 0.8 Mbit/s

            case .sd144p30, .sd144p25:
                return 600_000 // 0.6 Mbit/s

            case .sd128p30, .sd128p25:
                return 400_000 // 0.4 Mbit/s

            case .unknown:
                return 0
            }
        }

        static func from(resolution: String, fps: Int? = nil) -> Self {
            allCases.first { $0.rawValue.contains(resolution) && $0.refreshRate == (fps ?? 30) } ?? .unknown
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.height == rhs.height ? (lhs.refreshRate < rhs.refreshRate) : (lhs.height < rhs.height)
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
