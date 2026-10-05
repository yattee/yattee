//
//  LinkVideoResolver.swift
//  Yattee
//
//  Turns a link into a video and its streams, and queues downloads from them.
//  Shared by the Open Link sheet and URL scheme actions.
//

import Foundation

@MainActor
struct LinkVideoResolver {
    let appEnvironment: AppEnvironment

    /// Resolves a link to a playable video with its streams, captions and
    /// storyboards: YouTube/PeerTube through the matching source, direct media
    /// as-is, anything else through Yattee Server's extraction.
    func resolve(_ url: URL) async throws -> (Video, [Stream], [Caption], [Storyboard]) {
        let router = URLRouter()
        let destination = router.route(url)

        switch destination {
        case .video(let source, _):
            guard case .id(let videoID) = source else {
                throw LinkResolveError.notAVideo
            }
            // YouTube/PeerTube - use content-aware instance selection
            guard let instance = appEnvironment.instancesManager.instance(for: videoID.source) else {
                throw LinkResolveError.noInstanceAvailable
            }
            let (video, streams, captions, storyboards) = try await appEnvironment.contentService
                .videoWithProxyStreamsAndCaptionsAndStoryboards(
                    id: videoID.videoID,
                    instance: instance
                )
            return (video, streams, captions, storyboards)

        case .directMedia(let mediaURL):
            // Direct media URL - no extraction needed, no captions/storyboards
            let video = DirectMediaHelper.createVideo(from: mediaURL)
            let stream = DirectMediaHelper.createStream(from: mediaURL)
            return (video, [stream], [], [])

        case .externalVideo, nil:
            // A file mpv plays as-is needs no extraction, no captions/storyboards
            if let probe = await DirectMediaProbe.probe(url) {
                let video = DirectMediaHelper.createVideo(from: url, probe: probe)
                let stream = DirectMediaHelper.createStream(from: url, probe: probe)
                return (video, [stream], [], [])
            }
            // External URL - use Yattee Server (doesn't support storyboards)
            guard let instance = appEnvironment.instancesManager.yatteeServerInstance else {
                throw LinkResolveError.noYatteeServer
            }
            let (video, streams, captions) = try await appEnvironment.contentService
                .extractURL(url, instance: instance)
            return (video, streams, captions, [])

        default:
            throw LinkResolveError.notAVideo
        }
    }

    #if !os(tvOS)
    /// Enqueues a single video for download with already-fetched streams.
    func enqueueDownload(
        video: Video,
        streams: [Stream],
        captions: [Caption],
        storyboards: [Storyboard],
        quality: DownloadQuality,
        includeSubtitles: Bool
    ) async throws {
        // Select best video stream
        let videoStream = selectBestVideoStream(from: streams, maxQuality: quality)
        guard let videoStream else {
            throw DownloadError.noStreamAvailable
        }

        // Select audio stream if needed
        var audioStream: Stream?
        if videoStream.isVideoOnly {
            audioStream = selectBestAudioStream(
                from: streams,
                preferredLanguage: appEnvironment.settingsManager.preferredAudioLanguage
            )
        }

        // Select caption if enabled
        var caption: Caption?
        if includeSubtitles, let preferredLang = appEnvironment.settingsManager.preferredSubtitlesLanguage {
            caption = selectBestCaption(from: captions, preferredLanguage: preferredLang)
        }

        let audioCodec = videoStream.isMuxed ? videoStream.audioCodec : audioStream?.audioCodec
        let audioBitrate = videoStream.isMuxed ? nil : audioStream?.bitrate

        try await appEnvironment.downloadManager.enqueue(
            video,
            quality: videoStream.qualityLabel,
            formatID: videoStream.format,
            streamURL: videoStream.url,
            audioStreamURL: videoStream.isVideoOnly ? audioStream?.url : nil,
            captionURL: caption?.url,
            audioLanguage: audioStream?.audioLanguage,
            captionLanguage: caption?.languageCode,
            httpHeaders: videoStream.httpHeaders,
            storyboard: storyboards.highest(),
            dislikeCount: nil,
            videoCodec: videoStream.videoCodec,
            audioCodec: audioCodec,
            videoBitrate: videoStream.bitrate,
            audioBitrate: audioBitrate
        )
    }

    // MARK: - Stream Selection Helpers

    private func selectBestVideoStream(from streams: [Stream], maxQuality: DownloadQuality) -> Stream? {
        let maxRes = maxQuality.maxResolution

        let videoStreams = streams
            .filter { !$0.isAudioOnly && $0.resolution != nil }
            .filter {
                let format = StreamFormat.detect(from: $0)
                return format != .hls && format != .dash
            }
            .sorted { s1, s2 in
                let res1 = s1.resolution ?? .p360
                let res2 = s2.resolution ?? .p360
                if res1 != res2 { return res1 > res2 }
                if s1.isMuxed != s2.isMuxed { return s1.isMuxed }
                return HardwareCapabilities.shared.codecPriority(for: s1.videoCodec) >
                       HardwareCapabilities.shared.codecPriority(for: s2.videoCodec)
            }

        guard let maxRes else {
            return videoStreams.first
        }

        if let stream = videoStreams.first(where: { ($0.resolution ?? .p360) <= maxRes }) {
            return stream
        }

        return videoStreams.last
    }

    private func selectBestAudioStream(from streams: [Stream], preferredLanguage: String?) -> Stream? {
        let audioStreams = streams.filter { $0.isAudioOnly }

        if let preferred = preferredLanguage {
            if let match = audioStreams.first(where: { ($0.audioLanguage ?? "").hasPrefix(preferred) }) {
                return match
            }
        }

        if let original = audioStreams.first(where: { $0.isOriginalAudio }) {
            return original
        }

        return audioStreams.first
    }

    private func selectBestCaption(from captions: [Caption], preferredLanguage: String) -> Caption? {
        if let exact = captions.first(where: { $0.languageCode == preferredLanguage }) {
            return exact
        }
        if let prefix = captions.first(where: {
            $0.languageCode.hasPrefix(preferredLanguage) || $0.baseLanguageCode == preferredLanguage
        }) {
            return prefix
        }
        return nil
    }
    #endif
}

// MARK: - Errors
enum LinkResolveError: LocalizedError {
    case noInstanceAvailable
    case noYatteeServer
    case notAVideo

    var errorDescription: String? {
        switch self {
        case .noInstanceAvailable:
            return String(localized: "openLink.noInstance")
        case .noYatteeServer:
            return String(localized: "openLink.noYatteeServer")
        case .notAVideo:
            return String(localized: "openLink.notAVideo")
        }
    }
}
