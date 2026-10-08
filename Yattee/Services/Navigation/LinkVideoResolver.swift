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
            // YouTube pages that hold no video route nowhere; say so instead
            // of asking for an extraction that can only fail
            if destination == nil, router.isYouTubeHost(url.host) {
                throw LinkResolveError.unsupportedYouTubeLink
            }
            // A file mpv plays as-is needs no extraction, no captions/storyboards
            if let probe = await DirectMediaProbe.probe(url) {
                let video = DirectMediaHelper.createVideo(from: url, probe: probe)
                let stream = DirectMediaHelper.createStream(from: url, probe: probe)
                return (video, [stream], [], [])
            }
            // External URL - use Yattee Server (doesn't support storyboards).
            // Without one, a YouTube link Yattee can't parse (clips, posts) is
            // simply unsupported - asking for a server would mislead.
            guard let instance = appEnvironment.instancesManager.yatteeServerInstance else {
                throw router.isYouTubeHost(url.host)
                    ? LinkResolveError.unsupportedYouTubeLink
                    : LinkResolveError.noYatteeServer
            }
            let (video, streams, captions) = try await appEnvironment.contentService
                .extractURL(url, instance: instance)
            return (video, streams, captions, [])

        default:
            throw LinkResolveError.notAVideo
        }
    }

    /// Resolves a link to the screen that shows it: a video's details page
    /// (loaded here so a bad link fails before navigating), or the playlist /
    /// channel screen, which loads its own content. A `?t=` timestamp is
    /// carried to the details page's Play.
    func resolveDestination(_ url: URL) async throws -> NavigationDestination {
        let router = URLRouter()
        let url = router.unwrapped(url)
        let startTime = router.parseTimestamp(url)

        func details(_ video: Video) -> NavigationDestination {
            var context = VideoQueueContext.single(video)
            context.linkStartTime = startTime
            return .video(.loaded(video), queueContext: context)
        }

        let destination = router.route(url)
        switch destination {
        case .video(.id(let videoID), _):
            guard let instance = appEnvironment.instancesManager.instance(for: videoID.source) else {
                throw LinkResolveError.noInstanceAvailable
            }
            let video = try await appEnvironment.contentService.video(id: videoID.videoID, instance: instance)
            return details(video)

        case .video(.loaded(let video), _):
            return details(video)

        case .directMedia, .externalVideo, nil:
            let (video, _, _, _) = try await resolve(url)
            return details(video)

        case .some(let destination):
            return destination
        }
    }

    /// Plays a video opened from a link. A watch link inside a playlist
    /// (`watch?v=X&list=Y`) plays it with the playlist queued around it;
    /// if the playlist can't be loaded, the video plays alone.
    func play(_ video: Video, from url: URL?, startTime: TimeInterval?) async {
        let router = URLRouter()
        if let url, appEnvironment.queueManager.isQueueEnabled,
           let listID = router.youTubePlaylistContext(router.unwrapped(url)) {
            let source = PlaylistSource.remote(.global(listID), instance: nil)
            if let playlist = try? await playlist(for: source),
               let index = playlist.videos.firstIndex(where: { $0.id.videoID == video.id.videoID }) {
                var videos = playlist.videos
                videos[index] = video
                appEnvironment.queueManager.playFromList(
                    videos: videos,
                    index: index,
                    queueSource: .playlist(playlistID: listID, continuation: nil),
                    sourceLabel: playlist.title,
                    startTime: startTime
                )
                return
            }
        }
        appEnvironment.playerService.openVideo(video, startTime: startTime, forceStartTime: startTime != nil)
    }

    /// Loads a remote playlist with its videos from the instance suited to it.
    func playlist(for source: PlaylistSource) async throws -> Playlist {
        guard case .remote(let playlistID, let instance, _, _) = source else {
            throw LinkResolveError.notAVideo
        }
        guard let instance = instance
                ?? playlistID.source.flatMap({ appEnvironment.instancesManager.playlistInstance(for: $0) }) else {
            throw LinkResolveError.noInstanceAvailable
        }
        return try await appEnvironment.contentService.playlist(id: playlistID.playlistID, instance: instance)
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

    /// Resolves each link's streams and enqueues it for download.
    /// - Returns: How many links were queued and how many failed.
    func downloadLinks(
        _ urls: [URL],
        quality: DownloadQuality,
        includeSubtitles: Bool
    ) async -> (succeeded: Int, failed: Int) {
        var succeeded = 0
        var failed = 0
        for url in urls {
            do {
                let (video, streams, captions, storyboards) = try await resolve(url)
                try await enqueueDownload(
                    video: video,
                    streams: streams,
                    captions: captions,
                    storyboards: storyboards,
                    quality: quality,
                    includeSubtitles: includeSubtitles
                )
                succeeded += 1
            } catch {
                LoggingService.shared.warning(
                    "Open link download failed for \(url.absoluteString): \(error.localizedDescription)",
                    category: .downloads
                )
                failed += 1
            }
        }
        return (succeeded, failed)
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
    case unsupportedYouTubeLink

    var errorDescription: String? {
        switch self {
        case .noInstanceAvailable:
            return String(localized: "openLink.noInstance")
        case .noYatteeServer:
            return String(localized: "openLink.noYatteeServer")
        case .notAVideo:
            return String(localized: "openLink.notAVideo")
        case .unsupportedYouTubeLink:
            return String(localized: "openLink.unsupportedYouTubeLink")
        }
    }
}
