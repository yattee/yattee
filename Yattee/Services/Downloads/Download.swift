//
//  Download.swift
//  Yattee
//
//  Represents a video download.
//

import Foundation

/// Represents a video download.
struct Download: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let videoID: VideoID
    let title: String
    let channelName: String
    let channelID: String
    let channelThumbnailURL: URL?
    let channelSubscriberCount: Int?
    /// Channel/author URL for external sources (e.g., bilibili channel page)
    let channelURL: URL?
    let thumbnailURL: URL?
    let duration: TimeInterval
    let description: String?
    let viewCount: Int?
    let likeCount: Int?
    let dislikeCount: Int?
    let publishedAt: Date?
    let publishedText: String?
    let streamURL: URL

    /// Optional separate audio stream URL (for video-only streams)
    let audioStreamURL: URL?
    /// Optional caption URL for subtitle download
    let captionURL: URL?
    /// Language code for the audio track (e.g., "en", "ja")
    let audioLanguage: String?
    /// Language code for the caption (e.g., "en", "de")
    let captionLanguage: String?
    /// Custom HTTP headers required for downloading (cookies, referer, etc.)
    let httpHeaders: [String: String]?
    /// Storyboard metadata for offline seek preview
    let storyboard: Storyboard?

    var status: DownloadStatus
    var progress: Double
    var totalBytes: Int64
    var downloadedBytes: Int64
    var quality: String
    var formatID: String
    var localVideoPath: String?
    var localAudioPath: String?
    /// Path to downloaded caption file
    var localCaptionPath: String?
    /// Directory containing downloaded storyboard sprite sheets
    var localStoryboardPath: String?
    /// Path to downloaded video thumbnail for offline Now Playing artwork
    var localThumbnailPath: String?
    /// Path to downloaded channel thumbnail for offline display
    var localChannelThumbnailPath: String?
    var startedAt: Date?
    var completedAt: Date?
    var error: String?
    var priority: DownloadPriority
    var autoDelete: Bool
    var resumeData: Data?
    /// Resume data for audio download
    var audioResumeData: Data?
    var retryCount: Int
    /// Non-fatal warnings during download (e.g., "Subtitles failed to download")
    var warnings: [String]

    /// Current phase of multi-file download
    var downloadPhase: DownloadPhase
    /// Progress for video file (0.0 to 1.0)
    var videoProgress: Double
    /// Progress for audio file (0.0 to 1.0)
    var audioProgress: Double
    /// Total bytes for video file
    var videoTotalBytes: Int64
    /// Total bytes for audio file
    var audioTotalBytes: Int64

    /// Video codec (e.g., "avc1", "vp9", "av01")
    let videoCodec: String?
    /// Audio codec (e.g., "mp4a", "opus")
    let audioCodec: String?
    /// Video bitrate in bits per second
    let videoBitrate: Int?
    /// Audio bitrate in bits per second
    let audioBitrate: Int?

    /// Current download speed in bytes per second (not persisted)
    var downloadSpeed: Int64 = 0
    /// Last time bytes were recorded for speed calculation (not persisted)
    var lastSpeedUpdateTime: Date?
    /// Last bytes count for speed calculation (not persisted)
    var lastSpeedBytes: Int64 = 0

    /// Per-stream speed tracking (not persisted)
    var videoDownloadSpeed: Int64 = 0
    var audioDownloadSpeed: Int64 = 0
    var captionDownloadSpeed: Int64 = 0
    /// Caption progress (0.0 to 1.0)
    var captionProgress: Double = 0
    /// Total bytes for caption file
    var captionTotalBytes: Int64 = 0
    /// Storyboard download speed (not persisted)
    var storyboardDownloadSpeed: Int64 = 0
    /// Storyboard progress (0.0 to 1.0)
    var storyboardProgress: Double = 0
    /// Total bytes for all storyboard files
    var storyboardTotalBytes: Int64 = 0

    /// Bytes downloaded for video (for indeterminate progress display, not persisted)
    var videoDownloadedBytes: Int64 = 0
    /// Bytes downloaded for audio (for indeterminate progress display, not persisted)
    var audioDownloadedBytes: Int64 = 0
    /// Bytes downloaded for caption (for indeterminate progress display, not persisted)
    var captionDownloadedBytes: Int64 = 0

    // MARK: - Size Unknown Detection

    /// Whether video stream size is unknown (server didn't provide Content-Length)
    var videoSizeUnknown: Bool {
        videoTotalBytes <= 0 && videoProgress < 1.0
    }

    /// Whether audio stream size is unknown
    var audioSizeUnknown: Bool {
        audioStreamURL != nil && audioTotalBytes <= 0 && audioProgress < 1.0
    }

    /// Whether caption stream size is unknown
    var captionSizeUnknown: Bool {
        captionURL != nil && captionTotalBytes <= 0 && captionProgress < 1.0
    }

    /// Whether any active stream has unknown size (for overall indeterminate display)
    var hasIndeterminateProgress: Bool {
        let videoIndeterminate = videoProgress < 1.0 && videoTotalBytes <= 0
        let audioIndeterminate = audioStreamURL != nil && audioProgress < 1.0 && audioTotalBytes <= 0
        return videoIndeterminate || audioIndeterminate
    }

    // Don't persist speed-related fields
    enum CodingKeys: String, CodingKey {
        case id, videoID, title, channelName, channelID, channelThumbnailURL, channelSubscriberCount, channelURL
        case thumbnailURL, duration, description, viewCount, likeCount, dislikeCount
        case publishedAt, publishedText, streamURL, audioStreamURL, captionURL
        case audioLanguage, captionLanguage, httpHeaders, storyboard, status, progress, totalBytes, downloadedBytes
        case quality, formatID, localVideoPath, localAudioPath, localCaptionPath, localStoryboardPath, localThumbnailPath, localChannelThumbnailPath
        case startedAt, completedAt, error, priority, autoDelete, resumeData, audioResumeData
        case retryCount, warnings, downloadPhase, videoProgress, audioProgress, videoTotalBytes, audioTotalBytes
        case videoCodec, audioCodec, videoBitrate, audioBitrate
        case storyboardProgress, storyboardTotalBytes
    }

    // Custom decoder for backwards compatibility with downloads saved before 'warnings' was added
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        videoID = try container.decode(VideoID.self, forKey: .videoID)
        title = try container.decode(String.self, forKey: .title)
        channelName = try container.decode(String.self, forKey: .channelName)
        channelID = try container.decode(String.self, forKey: .channelID)
        channelThumbnailURL = try container.decodeIfPresent(URL.self, forKey: .channelThumbnailURL)
        channelSubscriberCount = try container.decodeIfPresent(Int.self, forKey: .channelSubscriberCount)
        channelURL = try container.decodeIfPresent(URL.self, forKey: .channelURL)
        thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        viewCount = try container.decodeIfPresent(Int.self, forKey: .viewCount)
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount)
        dislikeCount = try container.decodeIfPresent(Int.self, forKey: .dislikeCount)
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        publishedText = try container.decodeIfPresent(String.self, forKey: .publishedText)
        streamURL = try container.decode(URL.self, forKey: .streamURL)
        audioStreamURL = try container.decodeIfPresent(URL.self, forKey: .audioStreamURL)
        captionURL = try container.decodeIfPresent(URL.self, forKey: .captionURL)
        audioLanguage = try container.decodeIfPresent(String.self, forKey: .audioLanguage)
        captionLanguage = try container.decodeIfPresent(String.self, forKey: .captionLanguage)
        httpHeaders = try container.decodeIfPresent([String: String].self, forKey: .httpHeaders)
        storyboard = try container.decodeIfPresent(Storyboard.self, forKey: .storyboard)

        status = try container.decode(DownloadStatus.self, forKey: .status)
        progress = try container.decode(Double.self, forKey: .progress)
        totalBytes = try container.decode(Int64.self, forKey: .totalBytes)
        downloadedBytes = try container.decode(Int64.self, forKey: .downloadedBytes)
        quality = try container.decode(String.self, forKey: .quality)
        formatID = try container.decode(String.self, forKey: .formatID)
        localVideoPath = try container.decodeIfPresent(String.self, forKey: .localVideoPath)
        localAudioPath = try container.decodeIfPresent(String.self, forKey: .localAudioPath)
        localCaptionPath = try container.decodeIfPresent(String.self, forKey: .localCaptionPath)
        localStoryboardPath = try container.decodeIfPresent(String.self, forKey: .localStoryboardPath)
        localThumbnailPath = try container.decodeIfPresent(String.self, forKey: .localThumbnailPath)
        localChannelThumbnailPath = try container.decodeIfPresent(String.self, forKey: .localChannelThumbnailPath)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        priority = try container.decode(DownloadPriority.self, forKey: .priority)
        autoDelete = try container.decode(Bool.self, forKey: .autoDelete)
        resumeData = try container.decodeIfPresent(Data.self, forKey: .resumeData)
        audioResumeData = try container.decodeIfPresent(Data.self, forKey: .audioResumeData)
        retryCount = try container.decode(Int.self, forKey: .retryCount)

        // Backwards compatibility: 'warnings' was added later, default to empty array
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []

        downloadPhase = try container.decode(DownloadPhase.self, forKey: .downloadPhase)
        videoProgress = try container.decode(Double.self, forKey: .videoProgress)
        audioProgress = try container.decode(Double.self, forKey: .audioProgress)
        videoTotalBytes = try container.decode(Int64.self, forKey: .videoTotalBytes)
        audioTotalBytes = try container.decode(Int64.self, forKey: .audioTotalBytes)

        videoCodec = try container.decodeIfPresent(String.self, forKey: .videoCodec)
        audioCodec = try container.decodeIfPresent(String.self, forKey: .audioCodec)
        videoBitrate = try container.decodeIfPresent(Int.self, forKey: .videoBitrate)
        audioBitrate = try container.decodeIfPresent(Int.self, forKey: .audioBitrate)

        // Backwards compatibility: storyboard progress fields were added later
        storyboardProgress = try container.decodeIfPresent(Double.self, forKey: .storyboardProgress) ?? 0
        storyboardTotalBytes = try container.decodeIfPresent(Int64.self, forKey: .storyboardTotalBytes) ?? 0
    }

    init(
        video: Video,
        quality: String,
        formatID: String,
        streamURL: URL,
        audioStreamURL: URL? = nil,
        captionURL: URL? = nil,
        audioLanguage: String? = nil,
        captionLanguage: String? = nil,
        httpHeaders: [String: String]? = nil,
        storyboard: Storyboard? = nil,
        dislikeCount: Int? = nil,
        priority: DownloadPriority = .normal,
        autoDelete: Bool = false,
        videoCodec: String? = nil,
        audioCodec: String? = nil,
        videoBitrate: Int? = nil,
        audioBitrate: Int? = nil
    ) {
        self.id = UUID()
        self.videoID = video.id
        self.title = video.title
        self.channelName = video.author.name
        self.channelID = video.author.id
        self.channelThumbnailURL = video.author.thumbnailURL
        self.channelSubscriberCount = video.author.subscriberCount
        self.channelURL = video.author.url
        self.thumbnailURL = video.bestThumbnail?.url
        self.duration = video.duration
        self.description = video.description
        self.viewCount = video.viewCount
        self.likeCount = video.likeCount
        self.dislikeCount = dislikeCount
        self.publishedAt = video.publishedAt
        self.publishedText = video.publishedText
        self.streamURL = streamURL
        self.audioStreamURL = audioStreamURL
        self.captionURL = captionURL
        self.audioLanguage = audioLanguage
        self.captionLanguage = captionLanguage
        self.httpHeaders = httpHeaders
        self.storyboard = storyboard

        self.status = .queued
        self.progress = 0
        self.totalBytes = 0
        self.downloadedBytes = 0
        self.quality = quality
        self.formatID = formatID
        self.localVideoPath = nil
        self.localAudioPath = nil
        self.localCaptionPath = nil
        self.localStoryboardPath = nil
        self.localThumbnailPath = nil
        self.localChannelThumbnailPath = nil
        self.startedAt = nil
        self.completedAt = nil
        self.error = nil
        self.priority = priority
        self.autoDelete = autoDelete
        self.resumeData = nil
        self.audioResumeData = nil
        self.retryCount = 0
        self.warnings = []
        self.downloadPhase = .video
        self.videoProgress = 0
        self.audioProgress = 0
        self.videoTotalBytes = 0
        self.audioTotalBytes = 0
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.videoBitrate = videoBitrate
        self.audioBitrate = audioBitrate
    }

    /// Convert to a Video model for display purposes.
    func toVideo() -> Video {
        Video(
            id: videoID,
            title: title,
            description: description,
            author: Author(
                id: channelID,
                name: channelName,
                thumbnailURL: channelThumbnailURL,
                subscriberCount: channelSubscriberCount,
                url: channelURL
            ),
            duration: duration,
            publishedAt: publishedAt,
            publishedText: publishedText,
            viewCount: viewCount,
            likeCount: likeCount,
            thumbnails: thumbnailURL.map { [Thumbnail(url: $0, quality: .medium)] } ?? [],
            isLive: false,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }
}

// MARK: - Preview Data

extension Download {
    /// A sample completed download for SwiftUI previews.
    static var preview: Download {
        var download = Download(
            video: .preview,
            quality: "1080p",
            formatID: "137",
            streamURL: URL(string: "https://example.com/video.mp4")!,
            audioStreamURL: URL(string: "https://example.com/audio.m4a")!,
            captionURL: URL(string: "https://example.com/captions.vtt")!,
            audioLanguage: "en",
            captionLanguage: "en",
            videoCodec: "avc1",
            audioCodec: "mp4a",
            videoBitrate: 5_000_000,
            audioBitrate: 128_000
        )
        download.status = .completed
        download.progress = 1.0
        download.videoProgress = 1.0
        download.audioProgress = 1.0
        download.videoTotalBytes = 150_000_000
        download.audioTotalBytes = 5_000_000
        download.totalBytes = 155_000_000
        download.downloadedBytes = 155_000_000
        download.localVideoPath = "/Downloads/video.mp4"
        download.localAudioPath = "/Downloads/audio.m4a"
        download.localCaptionPath = "/Downloads/captions.vtt"
        download.completedAt = Date()
        return download
    }

    /// A sample muxed download (no separate audio) for SwiftUI previews.
    static var muxedPreview: Download {
        var download = Download(
            video: .preview,
            quality: "720p",
            formatID: "22",
            streamURL: URL(string: "https://example.com/muxed.mp4")!,
            videoCodec: "avc1",
            audioCodec: "mp4a",
            videoBitrate: 2_500_000,
            audioBitrate: 128_000
        )
        download.status = .completed
        download.progress = 1.0
        download.videoProgress = 1.0
        download.videoTotalBytes = 80_000_000
        download.totalBytes = 80_000_000
        download.downloadedBytes = 80_000_000
        download.localVideoPath = "/Downloads/muxed.mp4"
        download.completedAt = Date()
        return download
    }
}
