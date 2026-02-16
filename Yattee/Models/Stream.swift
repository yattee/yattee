//
//  Stream.swift
//  Yattee
//
//  Represents a video/audio stream for playback.
//

@preconcurrency import Foundation

/// Represents a playable video or audio stream.
struct Stream: Identifiable, Codable, Hashable, Sendable {
    /// Unique identifier combining resolution, fps and format.
    var id: String {
        let fpsString = fps.map { "\($0)" } ?? ""
        return "\(resolution?.description ?? "audio")\(fpsString)-\(format)"
    }

    /// The stream URL.
    let url: URL

    /// Stream resolution (nil for audio-only).
    let resolution: StreamResolution?

    /// Format/codec (mp4, webm, etc.).
    let format: String

    /// Video codec if applicable.
    let videoCodec: String?

    /// Audio codec.
    let audioCodec: String?

    /// Bitrate in bits per second.
    let bitrate: Int?

    /// File size in bytes if known.
    let fileSize: Int64?

    /// Whether this is an audio-only stream.
    let isAudioOnly: Bool

    /// Whether this is a video-only stream (no audio track).
    /// Note: Some sites (e.g., BitChute) don't provide resolution info.
    var isVideoOnly: Bool {
        // HLS/DASH are adaptive formats - codec info is in manifest, not metadata
        // They should never be classified as video-only based on missing codec info
        let isAdaptive = format.lowercased().contains("hls") ||
                         format.lowercased().contains("dash") ||
                         format.lowercased().contains("m3u8") ||
                         format.lowercased().contains("mpd")
        guard !isAdaptive else { return false }
        return !isAudioOnly && audioCodec == nil
    }

    /// Whether this stream has both video and audio (muxed).
    /// Note: Some sites (e.g., BitChute) don't provide resolution info.
    var isMuxed: Bool {
        !isAudioOnly && audioCodec != nil
    }

    /// Whether this is a live stream (HLS/DASH).
    let isLive: Bool

    /// MIME type.
    let mimeType: String?

    /// Audio language code (e.g., "en", "es", "ja").
    let audioLanguage: String?

    /// Audio track name/label.
    let audioTrackName: String?

    /// Whether this is the original audio track (not dubbed).
    let isOriginalAudio: Bool

    /// Custom HTTP headers required for streaming (cookies, referer, etc.).
    let httpHeaders: [String: String]?

    /// Frame rate (fps) if known.
    let fps: Int?

    // MARK: - Initialization

    init(
        url: URL,
        resolution: StreamResolution? = nil,
        format: String,
        videoCodec: String? = nil,
        audioCodec: String? = nil,
        bitrate: Int? = nil,
        fileSize: Int64? = nil,
        isAudioOnly: Bool = false,
        isLive: Bool = false,
        mimeType: String? = nil,
        audioLanguage: String? = nil,
        audioTrackName: String? = nil,
        isOriginalAudio: Bool = false,
        httpHeaders: [String: String]? = nil,
        fps: Int? = nil
    ) {
        self.url = url
        self.resolution = resolution
        self.format = format
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.bitrate = bitrate
        self.fileSize = fileSize
        self.isAudioOnly = isAudioOnly
        self.isLive = isLive
        self.mimeType = mimeType
        self.audioLanguage = audioLanguage
        self.audioTrackName = audioTrackName
        self.isOriginalAudio = isOriginalAudio
        self.httpHeaders = httpHeaders
        self.fps = fps
    }

    // MARK: - Computed Properties

    var qualityLabel: String {
        if isAudioOnly {
            return "Audio"
        }
        guard let resolution else { return "Unknown" }
        if let fps {
            return "\(resolution.height)p · \(fps)fps"
        }
        return resolution.description
    }

    var formattedFileSize: String? {
        guard let fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// Whether this stream is likely playable on Apple platforms.
    var isNativelyPlayable: Bool {
        // Apple platforms prefer H.264/H.265 in MP4/MOV containers
        let supportedFormats = ["mp4", "mov", "m4v", "m4a"]
        let supportedVideoCodecs = ["avc1", "hvc1", "hev1", "h264", "hevc"]

        if isAudioOnly {
            return true // Most audio codecs are supported
        }

        let formatSupported = supportedFormats.contains { format.lowercased().contains($0) }
        let codecSupported = videoCodec.map { codec in
            supportedVideoCodecs.contains { codec.lowercased().contains($0) }
        } ?? true

        return formatSupported && codecSupported
    }
}

// MARK: - Stream Resolution

struct StreamResolution: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    let width: Int
    let height: Int

    var description: String {
        "\(height)p"
    }

    // Common resolutions
    static let p360 = StreamResolution(width: 640, height: 360)
    static let p480 = StreamResolution(width: 854, height: 480)
    static let p720 = StreamResolution(width: 1280, height: 720)
    static let p1080 = StreamResolution(width: 1920, height: 1080)
    static let p1440 = StreamResolution(width: 2560, height: 1440)
    static let p2160 = StreamResolution(width: 3840, height: 2160)

    static func < (lhs: StreamResolution, rhs: StreamResolution) -> Bool {
        lhs.height < rhs.height
    }

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    init?(heightLabel: String) {
        let cleaned = heightLabel.replacingOccurrences(of: "p", with: "")
        guard let height = Int(cleaned) else { return nil }

        // Estimate width from height assuming 16:9
        let width = (height * 16) / 9
        self.init(width: width, height: height)
    }
}

// MARK: - URL Rewriting

extension Stream {
    /// Creates a copy of this stream with a different URL.
    /// Used for proxying streams through an instance.
    func withURL(_ newURL: URL) -> Stream {
        Stream(
            url: newURL,
            resolution: resolution,
            format: format,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            bitrate: bitrate,
            fileSize: fileSize,
            isAudioOnly: isAudioOnly,
            isLive: isLive,
            mimeType: mimeType,
            audioLanguage: audioLanguage,
            audioTrackName: audioTrackName,
            isOriginalAudio: isOriginalAudio,
            httpHeaders: httpHeaders,
            fps: fps
        )
    }
}

// MARK: - Preview Data

extension Stream {
    /// A sample 1080p muxed stream for SwiftUI previews.
    static var preview: Stream {
        Stream(
            url: URL(string: "https://example.com/video.mp4")!,
            resolution: .p1080,
            format: "mp4",
            videoCodec: "avc1",
            audioCodec: "mp4a",
            bitrate: 5_000_000,
            fileSize: 150_000_000,
            isAudioOnly: false,
            isLive: false,
            mimeType: "video/mp4",
            fps: 30
        )
    }

    /// A sample video-only stream (VP9) for SwiftUI previews.
    static var videoOnlyPreview: Stream {
        Stream(
            url: URL(string: "https://example.com/video-only.webm")!,
            resolution: .p1080,
            format: "webm",
            videoCodec: "vp9",
            audioCodec: nil,
            bitrate: 3_000_000,
            fileSize: 100_000_000,
            isAudioOnly: false,
            isLive: false,
            mimeType: "video/webm",
            fps: 60
        )
    }

    /// A sample audio-only stream for SwiftUI previews.
    static var audioPreview: Stream {
        Stream(
            url: URL(string: "https://example.com/audio.m4a")!,
            resolution: nil,
            format: "m4a",
            videoCodec: nil,
            audioCodec: "opus",
            bitrate: 128_000,
            fileSize: 5_000_000,
            isAudioOnly: true,
            isLive: false,
            mimeType: "audio/mp4",
            audioLanguage: "en",
            audioTrackName: "English",
            isOriginalAudio: true
        )
    }

    /// A sample HLS adaptive stream for SwiftUI previews.
    static var hlsPreview: Stream {
        Stream(
            url: URL(string: "https://example.com/master.m3u8")!,
            resolution: .p1080,
            format: "hls",
            isLive: false,
            mimeType: "application/vnd.apple.mpegurl",
            fps: 60
        )
    }

    /// A sample HLS stream without quality info for SwiftUI previews.
    static var hlsNoQualityPreview: Stream {
        Stream(
            url: URL(string: "https://example.com/master2.m3u8")!,
            resolution: nil,
            format: "hls",
            isLive: false,
            mimeType: "application/vnd.apple.mpegurl"
        )
    }
}
