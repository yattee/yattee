//
//  DirectMediaHelper.swift
//  Yattee
//
//  Helper for creating Video/Stream objects from direct media URLs.
//

import Foundation

/// Helper for handling direct media URLs (mp4, m3u8, etc.) without extraction.
enum DirectMediaHelper {
    /// Provider name for direct media URLs.
    static let provider = "direct_media"

    // MARK: - Supported Extensions

    /// Video file extensions that can be played directly.
    static let videoExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mkv", "avi", "webm", "wmv",
        "flv", "mpg", "mpeg", "3gp", "ts", "m2ts"
    ]

    /// Audio file extensions that can be played directly.
    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "ogg", "opus"
    ]

    /// Streaming format extensions (HLS, DASH).
    static let streamingExtensions: Set<String> = [
        "m3u8", "mpd"
    ]

    /// All supported media extensions.
    static var allExtensions: Set<String> {
        videoExtensions.union(audioExtensions).union(streamingExtensions)
    }

    // MARK: - Detection

    /// Checks if the URL points to a direct media file based on extension.
    static func isDirectMediaURL(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        return allExtensions.contains(pathExtension)
    }

    /// Checks if the URL is a streaming format (HLS/DASH).
    static func isStreamingURL(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        return streamingExtensions.contains(pathExtension)
    }

    /// Checks if the URL is an audio-only file.
    static func isAudioURL(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        return audioExtensions.contains(pathExtension)
    }

    // MARK: - Video/Stream Creation

    /// Creates a Video model from a direct media URL.
    static func createVideo(from url: URL) -> Video {
        let filename = url.lastPathComponent
        let title = (filename as NSString).deletingPathExtension
        let host = url.host ?? "Direct Media"

        return Video(
            id: VideoID(
                source: .extracted(extractor: provider, originalURL: url),
                videoID: url.absoluteString
            ),
            title: title.isEmpty ? filename : title,
            description: nil,
            author: Author(id: provider, name: host, hasRealChannelInfo: false),
            duration: 0, // Unknown until playback
            publishedAt: nil,
            publishedText: nil,
            viewCount: nil,
            likeCount: nil,
            thumbnails: [],
            isLive: isStreamingURL(url), // Treat HLS/DASH as potentially live
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }

    /// Creates a Stream from a direct media URL.
    static func createStream(from url: URL) -> Stream {
        let pathExtension = url.pathExtension.lowercased()
        let isAudio = isAudioURL(url)
        let isStreaming = isStreamingURL(url)

        return Stream(
            url: url,
            resolution: isAudio ? nil : .p720, // Default assumption for video
            format: pathExtension,
            videoCodec: isAudio ? nil : "unknown",
            audioCodec: "unknown",
            bitrate: nil,
            fileSize: nil,
            isAudioOnly: isAudio,
            isLive: isStreaming,
            mimeType: mimeType(for: pathExtension),
            audioLanguage: nil,
            audioTrackName: nil,
            isOriginalAudio: true,
            httpHeaders: nil,
            fps: nil
        )
    }

    // MARK: - MIME Type Mapping

    /// Returns the MIME type for a file extension.
    private static func mimeType(for extension: String) -> String? {
        switch `extension` {
        case "mp4", "m4v":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "mkv":
            return "video/x-matroska"
        case "avi":
            return "video/x-msvideo"
        case "webm":
            return "video/webm"
        case "wmv":
            return "video/x-ms-wmv"
        case "flv":
            return "video/x-flv"
        case "mpg", "mpeg":
            return "video/mpeg"
        case "3gp":
            return "video/3gpp"
        case "ts", "m2ts":
            return "video/mp2t"
        case "m3u8":
            return "application/vnd.apple.mpegurl"
        case "mpd":
            return "application/dash+xml"
        case "mp3":
            return "audio/mpeg"
        case "m4a":
            return "audio/mp4"
        case "aac":
            return "audio/aac"
        case "flac":
            return "audio/flac"
        case "wav":
            return "audio/wav"
        case "ogg":
            return "audio/ogg"
        case "opus":
            return "audio/opus"
        default:
            return nil
        }
    }
}
