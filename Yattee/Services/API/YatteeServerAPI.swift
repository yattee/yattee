//
//  YatteeServerAPI.swift
//  Yattee
//
//  Yattee Server API implementation for YouTube content.
//  The Yattee server provides an Invidious-compatible API, so this shares
//  response models with InvidiousAPI but handles unsupported endpoints.
//

@preconcurrency import Foundation

/// Yattee Server API client for fetching YouTube content.
/// Uses Invidious-compatible JSON format for responses.
actor YatteeServerAPI: InstanceAPI {
    private let httpClient: HTTPClient

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    // MARK: - InstanceAPI

    func trending(instance: Instance) async throws -> [Video] {
        // Yattee server proxies trending from Invidious if configured
        let endpoint = GenericEndpoint.get("/api/v1/trending")
        let response: [YatteeVideo] = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.map { $0.toVideo() }
    }

    func popular(instance: Instance) async throws -> [Video] {
        // Yattee server proxies popular from Invidious if configured
        let endpoint = GenericEndpoint.get("/api/v1/popular")
        let response: [YatteeVideo] = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.map { $0.toVideo() }
    }

    func search(query: String, instance: Instance, page: Int, filters: SearchFilters = .defaults) async throws -> SearchResult {
        var queryParams: [String: String] = [
            "q": query,
            "page": String(page),
            "type": filters.type.rawValue
        ]

        if filters.sort != .relevance {
            queryParams["sort"] = filters.sort.rawValue
        }
        if filters.date != .any {
            queryParams["date"] = filters.date.rawValue
        }
        if filters.duration != .any {
            queryParams["duration"] = filters.duration.rawValue
        }

        let endpoint = GenericEndpoint.get("/api/v1/search", query: queryParams)
        let response: [YatteeSearchItem] = try await httpClient.fetch(endpoint, baseURL: instance.url)

        // Helper to detect playlist IDs that may be returned as "video" type
        // YouTube playlist IDs start with: PL (user playlist), RD (mix), OL (offline mix), UU (uploads)
        func isPlaylistID(_ id: String) -> Bool {
            id.hasPrefix("PL") || id.hasPrefix("RD") || id.hasPrefix("OL") || id.hasPrefix("UU")
        }

        var videos: [Video] = []
        var channels: [Channel] = []
        var playlists: [Playlist] = []
        var orderedItems: [OrderedSearchItem] = []

        for item in response {
            switch item {
            case .video(let video):
                if isPlaylistID(video.videoId) {
                    // Convert misidentified playlist
                    let playlist = Playlist(
                        id: .global(video.videoId),
                        title: video.title,
                        author: Author(id: video.authorId, name: video.author),
                        videoCount: 0,
                        thumbnailURL: video.videoThumbnails?.first?.thumbnailURL
                    )
                    playlists.append(playlist)
                    orderedItems.append(.playlist(playlist))
                } else {
                    let v = video.toVideo()
                    videos.append(v)
                    orderedItems.append(.video(v))
                }
            case .channel(let channel):
                let c = channel.toChannel()
                channels.append(c)
                orderedItems.append(.channel(c))
            case .playlist(let playlist):
                let p = playlist.toPlaylist()
                playlists.append(p)
                orderedItems.append(.playlist(p))
            case .unknown:
                break
            }
        }

        // Determine if there are more pages based on whether we got results
        let hasResults = !videos.isEmpty || !channels.isEmpty || !playlists.isEmpty
        return SearchResult(
            videos: videos,
            channels: channels,
            playlists: playlists,
            orderedItems: orderedItems,
            nextPage: hasResults ? page + 1 : nil
        )
    }

    func searchSuggestions(query: String, instance: Instance) async throws -> [String] {
        let endpoint = GenericEndpoint.get("/api/v1/search/suggestions", query: [
            "q": query
        ])
        return try await httpClient.fetch(endpoint, baseURL: instance.url)
    }

    func video(id: String, instance: Instance) async throws -> Video {
        let endpoint = GenericEndpoint.get("/api/v1/videos/\(id)")
        let response: YatteeVideoDetails = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.toVideo()
    }

    func channel(id: String, instance: Instance) async throws -> Channel {
        let endpoint = GenericEndpoint.get("/api/v1/channels/\(id)")
        let response: YatteeChannel = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.toChannel()
    }

    func channelVideos(id: String, instance: Instance, continuation: String?) async throws -> ChannelVideosPage {
        var query: [String: String] = [:]
        if let continuation {
            query["continuation"] = continuation
        }
        let endpoint = GenericEndpoint.get("/api/v1/channels/\(id)/videos", query: query)
        let response: YatteeChannelVideosWithContinuation = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return ChannelVideosPage(
            videos: response.videos.map { $0.toVideo() },
            continuation: response.continuation
        )
    }

    func channelPlaylists(id: String, instance: Instance, continuation: String?) async throws -> ChannelPlaylistsPage {
        var query: [String: String] = [:]
        if let continuation {
            query["continuation"] = continuation
        }
        let endpoint = GenericEndpoint.get("/api/v1/channels/\(id)/playlists", query: query)
        let response: YatteeChannelPlaylists = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return ChannelPlaylistsPage(
            playlists: response.playlists.map { $0.toPlaylist() },
            continuation: response.continuation
        )
    }

    func channelShorts(id: String, instance: Instance, continuation: String?) async throws -> ChannelVideosPage {
        var query: [String: String] = [:]
        if let continuation {
            query["continuation"] = continuation
        }
        let endpoint = GenericEndpoint.get("/api/v1/channels/\(id)/shorts", query: query)
        let response: YatteeChannelVideosWithContinuation = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return ChannelVideosPage(
            videos: response.videos.map { $0.toVideo() },
            continuation: response.continuation
        )
    }

    func channelStreams(id: String, instance: Instance, continuation: String?) async throws -> ChannelVideosPage {
        var query: [String: String] = [:]
        if let continuation {
            query["continuation"] = continuation
        }
        let endpoint = GenericEndpoint.get("/api/v1/channels/\(id)/streams", query: query)
        let response: YatteeChannelVideosWithContinuation = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return ChannelVideosPage(
            videos: response.videos.map { $0.toVideo() },
            continuation: response.continuation
        )
    }

    func playlist(id: String, instance: Instance) async throws -> Playlist {
        let endpoint = GenericEndpoint.get("/api/v1/playlists/\(id)")
        let response: YatteePlaylist = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.toPlaylist()
    }

    func comments(videoID: String, instance: Instance, continuation: String?) async throws -> CommentsPage {
        // Yattee server proxies comments through Invidious if configured
        var query: [String: String] = [:]
        if let continuation {
            query["continuation"] = continuation
        }
        let endpoint = GenericEndpoint.get("/api/v1/comments/\(videoID)", query: query)
        do {
            let response: YatteeComments = try await httpClient.fetch(endpoint, baseURL: instance.url)
            return CommentsPage(
                comments: response.comments.map { $0.toComment() },
                continuation: response.continuation
            )
        } catch APIError.notFound {
            throw APIError.commentsDisabled
        } catch APIError.httpError(statusCode: 503, _) {
            // Invidious not configured on server
            throw APIError.commentsDisabled
        }
    }

    func streams(videoID: String, instance: Instance) async throws -> [Stream] {
        let endpoint = GenericEndpoint.get("/api/v1/videos/\(videoID)")
        let response: YatteeVideoDetails = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.toStreams()
    }

    func captions(videoID: String, instance: Instance) async throws -> [Caption] {
        let endpoint = GenericEndpoint.get("/api/v1/videos/\(videoID)")
        let response: YatteeVideoDetails = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.toCaptions(baseURL: instance.url)
    }

    func channelSearch(id: String, query: String, instance: Instance, page: Int) async throws -> ChannelSearchPage {
        let endpoint = GenericEndpoint.get("/api/v1/channels/\(id)/search", query: [
            "q": query,
            "page": String(page)
        ])
        // Yattee Server returns {"videos": [...]} wrapper, not a plain array
        let response: YatteeChannelSearchResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)

        var items: [ChannelSearchItem] = []

        for video in response.videos {
            items.append(.video(video.toVideo()))
        }

        // Has more pages if we got results
        let hasResults = !items.isEmpty
        return ChannelSearchPage(items: items, nextPage: hasResults ? page + 1 : nil)
    }

    /// Fetches video details, streams, and captions in a single API call.
    func videoWithStreamsAndCaptions(id: String, instance: Instance) async throws -> (video: Video, streams: [Stream], captions: [Caption]) {
        let result = try await videoWithStreamsAndCaptionsAndStoryboards(id: id, instance: instance)
        return (video: result.video, streams: result.streams, captions: result.captions)
    }

    func videoWithStreamsAndCaptionsAndStoryboards(id: String, instance: Instance) async throws -> (video: Video, streams: [Stream], captions: [Caption], storyboards: [Storyboard]) {
        let endpoint = GenericEndpoint.get("/api/v1/videos/\(id)")
        let response: YatteeVideoDetails = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return (
            video: response.toVideo(),
            streams: response.toStreams(),
            captions: response.toCaptions(baseURL: instance.url),
            storyboards: response.toStoryboards(instanceBaseURL: instance.url)
        )
    }

    // MARK: - Proxy Streams for Downloads

    /// Fetches streams with URLs that proxy through the Yattee Server for faster LAN downloads.
    /// The proxy URLs point to the server's /proxy/fast/{video_id}?itag=X endpoint instead of
    /// directly to YouTube CDN, allowing the server to download at full speed and serve locally.
    func proxyStreams(videoID: String, instance: Instance) async throws -> [Stream] {
        let endpoint = GenericEndpoint.get("/api/v1/videos/\(videoID)", query: ["proxy": "true"])
        let response: YatteeVideoDetails = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.toStreams()
    }

    /// Fetches video details, proxy streams, captions, and storyboards in a single API call.
    /// Use this for downloads to get streams that route through the server.
    func videoWithProxyStreamsAndCaptionsAndStoryboards(id: String, instance: Instance) async throws -> (video: Video, streams: [Stream], captions: [Caption], storyboards: [Storyboard]) {
        let endpoint = GenericEndpoint.get("/api/v1/videos/\(id)", query: ["proxy": "true"])
        let response: YatteeVideoDetails = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return (
            video: response.toVideo(),
            streams: response.toStreams(),
            captions: response.toCaptions(baseURL: instance.url),
            storyboards: response.toStoryboards(instanceBaseURL: instance.url)
        )
    }

    // MARK: - External URL Extraction

    /// Extracts video information from any URL that yt-dlp supports.
    ///
    /// This enables playback from sites like Vimeo, Twitter, TikTok, and hundreds
    /// of other sites supported by yt-dlp.
    ///
    /// - Parameters:
    ///   - url: The URL to extract (e.g., https://vimeo.com/12345)
    ///   - instance: The Yattee Server instance to use for extraction
    /// - Returns: Tuple of video, streams, and captions
    /// - Throws: `ExtractionError` if extraction fails
    func extractURL(_ url: URL, instance: Instance) async throws -> (video: Video, streams: [Stream], captions: [Caption]) {
        let endpoint = GenericEndpoint(
            path: "/api/v1/extract",
            queryItems: [URLQueryItem(name: "url", value: url.absoluteString)],
            timeout: 180  // 3 minutes for slow site extraction
        )
        let response: YatteeExternalVideo = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return (
            video: response.toVideo(originalURL: url),
            streams: response.toStreams(),
            captions: response.toCaptions(baseURL: instance.url)
        )
    }

    /// Extracts channel/user videos from any URL that yt-dlp supports.
    ///
    /// This works with Vimeo, Dailymotion, SoundCloud, and many other sites.
    /// Note that some sites (like Twitter/X) may not support channel extraction.
    ///
    /// - Parameters:
    ///   - url: The channel/user URL to extract (e.g., https://vimeo.com/username)
    ///   - page: Page number (1-based)
    ///   - instance: The Yattee Server instance to use for extraction
    /// - Returns: Tuple of channel, videos list, and optional continuation token for next page
    /// - Throws: `HTTPError` if extraction fails (e.g., site doesn't support channel extraction)
    func extractChannel(url: URL, page: Int = 1, instance: Instance) async throws -> (channel: Channel, videos: [Video], continuation: String?) {
        let endpoint = GenericEndpoint(
            path: "/api/v1/extract/channel",
            queryItems: [
                URLQueryItem(name: "url", value: url.absoluteString),
                URLQueryItem(name: "page", value: String(page))
            ],
            timeout: 180  // 3 minutes for slow site extraction
        )
        let response: YatteeExternalChannel = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return (
            channel: response.toChannel(originalURL: url),
            videos: response.toVideos(channelURL: url),
            continuation: response.continuation
        )
    }

    // MARK: - Stateless Feed Endpoints

    /// Fetches feed using stateless POST endpoint with channel list.
    func postFeed(channels: [StatelessChannelRequest], limit: Int, offset: Int, instance: Instance) async throws -> StatelessFeedResponse {
        let body = StatelessFeedRequest(channels: channels, limit: limit, offset: offset)
        let endpoint = GenericEndpoint.post("/api/v1/feed", body: body)
        return try await httpClient.fetch(endpoint, baseURL: instance.url)
    }

    /// Checks feed status for given channels (lightweight polling).
    func postFeedStatus(channels: [StatelessChannelStatusRequest], instance: Instance) async throws -> StatelessFeedStatusResponse {
        let body = StatelessFeedStatusRequest(channels: channels)
        let endpoint = GenericEndpoint.post("/api/v1/feed/status", body: body)
        return try await httpClient.fetch(endpoint, baseURL: instance.url)
    }

    // MARK: - Channel Metadata

    /// Fetches cached channel metadata (subscriber counts, verified status) for multiple channels.
    /// Returns only cached data - no API calls to YouTube.
    func channelsMetadata(channelIDs: [String], instance: Instance) async throws -> ChannelsMetadataResponse {
        let body = ChannelMetadataRequest(channelIds: channelIDs)
        let endpoint = GenericEndpoint.post("/api/v1/channels/metadata", body: body)
        return try await httpClient.fetch(endpoint, baseURL: instance.url)
    }

    // MARK: - Server Info

    /// Fetches server info including version, dependencies, and enabled sites.
    func fetchServerInfo(for instance: Instance) async throws -> InstanceDetectorModels.YatteeServerFullInfo {
        let endpoint = GenericEndpoint.get("/info")
        return try await httpClient.fetch(endpoint, baseURL: instance.url)
    }
}

// MARK: - Server Feed Models

/// A video from the server feed.
struct ServerFeedVideo: Decodable, Sendable {
    let type: String
    let videoId: String
    let title: String
    let author: String
    let authorId: String
    let lengthSeconds: Int
    let published: Int64?
    let publishedText: String?
    let viewCount: Int?
    let videoThumbnails: [YatteeThumbnail]?
    let extractor: String
    let videoUrl: String?
    let isUpcoming: Bool?
    let premiereTimestamp: Int64?

    func toVideo() -> Video? {
        // Determine content source based on extractor
        let videoID: VideoID
        if extractor == "youtube" {
            videoID = .global(videoId)
        } else if let urlString = videoUrl, let url = URL(string: urlString) {
            videoID = .extracted(videoId, extractor: extractor, originalURL: url)
        } else {
            // Fallback to global with extractor as provider
            videoID = .global(videoId, provider: extractor)
        }

        return Video(
            id: videoID,
            title: title,
            description: nil,
            author: Author(id: authorId, name: author),
            duration: TimeInterval(lengthSeconds),
            publishedAt: published.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            publishedText: publishedText,
            viewCount: viewCount,
            likeCount: nil,
            thumbnails: videoThumbnails?.map { $0.toThumbnail() } ?? [],
            isLive: false,
            isUpcoming: isUpcoming ?? false,
            scheduledStartTime: premiereTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}

// MARK: - Stateless Feed Models

/// Channel info for stateless feed request.
struct StatelessChannelRequest: Encodable, Sendable {
    let channelId: String
    let site: String
    let channelName: String?
    let channelUrl: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case channelId = "channel_id"
        case site
        case channelName = "channel_name"
        case channelUrl = "channel_url"
        case avatarUrl = "avatar_url"
    }

    init(channelId: String, site: String, channelName: String?, channelUrl: String? = nil, avatarUrl: String?) {
        self.channelId = channelId
        self.site = site
        self.channelName = channelName
        self.channelUrl = channelUrl
        self.avatarUrl = avatarUrl
    }
}

/// Minimal channel info for status check.
struct StatelessChannelStatusRequest: Encodable, Sendable {
    let channelId: String
    let site: String

    enum CodingKeys: String, CodingKey {
        case channelId = "channel_id"
        case site
    }
}

/// Request body for stateless feed endpoint.
struct StatelessFeedRequest: Encodable, Sendable {
    let channels: [StatelessChannelRequest]
    let limit: Int
    let offset: Int
}

/// Request body for stateless feed status endpoint.
struct StatelessFeedStatusRequest: Encodable, Sendable {
    let channels: [StatelessChannelStatusRequest]
}

/// Response from stateless feed endpoint.
struct StatelessFeedResponse: Decodable, Sendable {
    let status: String
    let videos: [ServerFeedVideo]
    let total: Int
    let hasMore: Bool
    let readyCount: Int?
    let pendingCount: Int?
    let errorCount: Int?
    let etaSeconds: Int?

    var isReady: Bool { status == "ready" }

    func toVideos() -> [Video] {
        videos.compactMap { $0.toVideo() }
    }
}

/// Response from stateless feed status endpoint.
struct StatelessFeedStatusResponse: Decodable, Sendable {
    let status: String
    let readyCount: Int
    let pendingCount: Int
    let errorCount: Int

    var isReady: Bool { status == "ready" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        readyCount = try container.decode(Int.self, forKey: .readyCount)
        pendingCount = try container.decode(Int.self, forKey: .pendingCount)
        // Default to 0 for backwards compatibility with older server versions
        errorCount = try container.decodeIfPresent(Int.self, forKey: .errorCount) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case readyCount
        case pendingCount
        case errorCount
    }
}

// MARK: - Channel Metadata Models

/// Request body for channels metadata endpoint.
struct ChannelMetadataRequest: Encodable, Sendable {
    let channelIds: [String]

    enum CodingKeys: String, CodingKey {
        case channelIds = "channel_ids"
    }
}

/// Response from channels metadata endpoint.
struct ChannelsMetadataResponse: Decodable, Sendable {
    let channels: [ChannelMetadataItem]
}

/// Cached metadata for a single channel.
/// Note: Uses automatic snake_case to camelCase conversion via HTTPClient's keyDecodingStrategy.
struct ChannelMetadataItem: Decodable, Sendable {
    let channelId: String
    let subscriberCount: Int?
    /// SQLite stores booleans as integers (0/1)
    let isVerified: Int?

    var isVerifiedBool: Bool {
        isVerified == 1
    }
}

// MARK: - yt-dlp Server Response Models (Invidious-compatible)

private struct YatteeVideo: Decodable, Sendable {
    let videoId: String
    let title: String
    let description: String?
    let author: String
    let authorId: String
    let authorUrl: String?
    let lengthSeconds: Int
    let published: Int64?
    let publishedText: String?
    let viewCount: Int?
    let likeCount: Int?
    let videoThumbnails: [YatteeThumbnail]?
    let liveNow: Bool?
    let isUpcoming: Bool?
    let premiereTimestamp: Int64?

    nonisolated func toVideo() -> Video {
        Video(
            id: .global(videoId),
            title: title,
            description: description,
            author: Author(id: authorId, name: author),
            duration: TimeInterval(lengthSeconds),
            publishedAt: published.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            publishedText: publishedText,
            viewCount: viewCount,
            likeCount: likeCount,
            thumbnails: videoThumbnails?.map { $0.toThumbnail() } ?? [],
            isLive: liveNow ?? false,
            isUpcoming: isUpcoming ?? false,
            scheduledStartTime: premiereTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}

private struct YatteeVideoDetails: Decodable, Sendable {
    let videoId: String
    let title: String
    let description: String?
    let descriptionHtml: String?
    let author: String
    let authorId: String
    let authorThumbnails: [YatteeThumbnail]?
    let subCountText: String?
    let lengthSeconds: Int
    let published: Int64?
    let publishedText: String?
    let viewCount: Int?
    let likeCount: Int?
    let videoThumbnails: [YatteeThumbnail]?
    let liveNow: Bool?
    let isUpcoming: Bool?
    let premiereTimestamp: Int64?
    let hlsUrl: String?
    let dashUrl: String?
    let formatStreams: [YatteeFormatStream]?
    let adaptiveFormats: [YatteeAdaptiveFormat]?
    let captions: [YatteeCaption]?
    let storyboards: [YatteeStoryboard]?
    let recommendedVideos: [YatteeRecommendedVideo]?

    /// Parses subscriber count from text like "1.78M" or "500K"
    nonisolated var subscriberCount: Int? {
        guard let text = subCountText else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespaces).uppercased()

        let multiplier: Double
        var numericPart = cleaned

        if cleaned.hasSuffix("B") {
            multiplier = 1_000_000_000
            numericPart = String(cleaned.dropLast())
        } else if cleaned.hasSuffix("M") {
            multiplier = 1_000_000
            numericPart = String(cleaned.dropLast())
        } else if cleaned.hasSuffix("K") {
            multiplier = 1_000
            numericPart = String(cleaned.dropLast())
        } else {
            multiplier = 1
        }

        guard let value = Double(numericPart) else { return nil }
        return Int(value * multiplier)
    }

    nonisolated func toVideo() -> Video {
        // Convert recommended videos, limiting to 12
        let related: [Video]? = recommendedVideos?.prefix(12).map { $0.toVideo() }

        return Video(
            id: .global(videoId),
            title: title,
            description: description,
            author: Author(
                id: authorId,
                name: author,
                thumbnailURL: authorThumbnails?.authorThumbnailURL,
                subscriberCount: subscriberCount
            ),
            duration: TimeInterval(lengthSeconds),
            publishedAt: published.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            publishedText: publishedText,
            viewCount: viewCount,
            likeCount: likeCount,
            thumbnails: videoThumbnails?.map { $0.toThumbnail() } ?? [],
            isLive: liveNow ?? false,
            isUpcoming: isUpcoming ?? false,
            scheduledStartTime: premiereTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            relatedVideos: related
        )
    }

    nonisolated func toStreams() -> [Stream] {
        var streams: [Stream] = []

        // Add HLS stream (adaptive - works for both live and on-demand content)
        if let hlsUrl, let url = URL(string: hlsUrl) {
            streams.append(Stream(
                url: url,
                resolution: nil,
                format: "hls",
                isLive: liveNow ?? false,
                mimeType: "application/x-mpegURL"
            ))
        }

        // Add DASH stream (adaptive - supports VP9, AV1, higher qualities)
        if let dashUrl, let url = URL(string: dashUrl) {
            streams.append(Stream(
                url: url,
                resolution: nil,
                format: "dash",
                isLive: liveNow ?? false,
                mimeType: "application/dash+xml"
            ))
        }

        // Add format streams (combined audio+video)
        if let formatStreams {
            streams.append(contentsOf: formatStreams.compactMap { $0.toStream(isLive: liveNow ?? false) })
        }

        // Add adaptive formats (separate audio/video)
        if let adaptiveFormats {
            streams.append(contentsOf: adaptiveFormats.compactMap { $0.toStream(isLive: liveNow ?? false) })
        }

        return streams
    }

    nonisolated func toCaptions(baseURL: URL) -> [Caption] {
        guard let captions else { return [] }
        return captions.compactMap { $0.toCaption(baseURL: baseURL) }
    }

    nonisolated func toStoryboards(instanceBaseURL: URL) -> [Storyboard] {
        storyboards?.compactMap { $0.toStoryboard(instanceBaseURL: instanceBaseURL) } ?? []
    }
}

private struct YatteeStoryboard: Decodable, Sendable {
    let url: String?
    let templateUrl: String?
    let width: Int
    let height: Int
    let count: Int
    let interval: Int
    let storyboardWidth: Int
    let storyboardHeight: Int
    let storyboardCount: Int

    nonisolated func toStoryboard(instanceBaseURL: URL) -> Storyboard? {
        // templateUrl is the direct YouTube URL (may be blocked)
        // url is the proxied URL through the instance (preferred)
        guard templateUrl != nil || url != nil else { return nil }
        return Storyboard(
            proxyUrl: url,
            templateUrl: templateUrl ?? "",
            instanceBaseURL: instanceBaseURL,
            width: width,
            height: height,
            count: count,
            interval: interval,
            storyboardWidth: storyboardWidth,
            storyboardHeight: storyboardHeight,
            storyboardCount: storyboardCount
        )
    }
}

/// Recommended video from Yattee Server video details response.
private struct YatteeRecommendedVideo: Decodable, Sendable {
    let videoId: String
    let title: String
    let author: String
    let authorId: String
    let authorUrl: String?
    let videoThumbnails: [YatteeThumbnail]?
    let lengthSeconds: Int
    let viewCountText: String?
    let viewCount: Int?

    nonisolated func toVideo() -> Video {
        // Parse view count from text if numeric viewCount not available
        let views: Int? = viewCount ?? parseViewCount(from: viewCountText)

        return Video(
            id: .global(videoId),
            title: title,
            description: nil,
            author: Author(id: authorId, name: author),
            duration: TimeInterval(lengthSeconds),
            publishedAt: nil,
            publishedText: nil,
            viewCount: views,
            likeCount: nil,
            thumbnails: videoThumbnails?.map { $0.toThumbnail() } ?? [],
            isLive: false,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }

    /// Parses view count from text like "1.2M views" or "500K views".
    private nonisolated func parseViewCount(from text: String?) -> Int? {
        guard let text else { return nil }
        let cleaned = text
            .replacingOccurrences(of: " views", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
            .uppercased()

        let multiplier: Double
        var numericPart = cleaned

        if cleaned.hasSuffix("B") {
            multiplier = 1_000_000_000
            numericPart = String(cleaned.dropLast())
        } else if cleaned.hasSuffix("M") {
            multiplier = 1_000_000
            numericPart = String(cleaned.dropLast())
        } else if cleaned.hasSuffix("K") {
            multiplier = 1_000
            numericPart = String(cleaned.dropLast())
        } else {
            multiplier = 1
        }

        guard let value = Double(numericPart) else { return nil }
        return Int(value * multiplier)
    }
}

// MARK: - External Channel Model (for non-YouTube channel extraction)

private struct YatteeExternalChannel: Decodable, Sendable {
    let author: String
    let authorId: String
    let authorUrl: String
    let extractor: String
    let videos: [YatteeExternalVideoListItem]
    let continuation: String?

    nonisolated func toChannel(originalURL: URL) -> Channel {
        Channel(
            id: ChannelID.extracted(authorId, extractor: extractor, originalURL: originalURL),
            name: author,
            description: nil,
            subscriberCount: nil,
            videoCount: videos.count,
            thumbnailURL: nil,
            bannerURL: nil,
            isVerified: false
        )
    }

    nonisolated func toVideos(channelURL: URL) -> [Video] {
        videos.compactMap { $0.toVideo(channelURL: channelURL, extractor: extractor) }
    }
}

private struct YatteeExternalVideoListItem: Decodable, Sendable {
    let videoId: String
    let title: String
    let description: String?
    let author: String
    let authorId: String
    let authorUrl: String?
    let lengthSeconds: Int
    let published: Int64?
    let publishedText: String?
    let viewCount: Int?
    let viewCountText: String?
    let videoThumbnails: [YatteeThumbnail]?
    let extractor: String?
    let videoUrl: String?  // Original video URL for extraction

    nonisolated func toVideo(channelURL: URL, extractor: String) -> Video {
        let extractorName = self.extractor ?? extractor
        // Use the actual video URL from the server, fall back to channel URL
        let videoURL = videoUrl.flatMap { URL(string: $0) } ?? channelURL

        return Video(
            id: .extracted(videoId, extractor: extractorName, originalURL: videoURL),
            title: title,
            description: description,
            author: Author(
                id: authorId.isEmpty ? extractorName : authorId,
                name: author.isEmpty ? extractorName.capitalized : author,
                url: authorUrl.flatMap { URL(string: $0) } ?? channelURL,
                hasRealChannelInfo: true  // Channel videos always have valid channel URL
            ),
            duration: TimeInterval(lengthSeconds),
            publishedAt: published.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            publishedText: publishedText,
            viewCount: viewCount,
            likeCount: nil,
            thumbnails: videoThumbnails?.map { $0.toThumbnail() } ?? [],
            isLive: false,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }
}

private struct YatteeCaption: Decodable, Sendable {
    let label: String
    let languageCode: String
    let url: String
    let autoGenerated: Bool?

    nonisolated func toCaption(baseURL: URL) -> Caption? {
        // Caption URLs from server are full URLs like:
        // http://server/api/v1/captions/{id}/content?lang=en
        var captionURL: URL?
        if url.hasPrefix("/") {
            captionURL = URL(string: url, relativeTo: baseURL)?.absoluteURL
        } else {
            captionURL = URL(string: url)
        }

        // Ensure caption URL uses same scheme as instance (fixes http/https mismatch from reverse proxy)
        if var urlComponents = captionURL.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: true) }),
           let instanceScheme = baseURL.scheme,
           urlComponents.host == baseURL.host {
            urlComponents.scheme = instanceScheme
            captionURL = urlComponents.url
        }

        guard let captionURL else { return nil }
        return Caption(
            label: label,
            languageCode: languageCode,
            url: captionURL
        )
    }
}

private struct YatteeFormatStream: Decodable, Sendable {
    let url: String?
    let itag: String?
    let type: String?
    let quality: String?
    let container: String?
    let encoding: String?
    let resolution: String?
    let width: Int?
    let height: Int?
    let size: String?
    let fps: Int?
    let httpHeaders: [String: String]?

    nonisolated func toStream(isLive: Bool = false) -> Stream? {
        guard let urlString = url, let streamUrl = URL(string: urlString) else { return nil }

        let audioCodec = parseAudioCodec(from: type)
        let videoCodec = encoding ?? parseVideoCodec(from: type)

        // Prefer actual width/height from API, fallback to parsing from resolution label
        let streamResolution: StreamResolution?
        if let w = width, let h = height, w > 0, h > 0 {
            streamResolution = StreamResolution(width: w, height: h)
        } else {
            streamResolution = resolution.flatMap { StreamResolution(heightLabel: $0) }
        }

        return Stream(
            url: streamUrl,
            resolution: streamResolution,
            format: container ?? "unknown",
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            isLive: isLive,
            mimeType: type,
            httpHeaders: httpHeaders,
            fps: fps
        )
    }

    private nonisolated func parseVideoCodec(from mimeType: String?) -> String? {
        guard let mimeType else { return nil }

        guard let codecsRange = mimeType.range(of: "codecs=\"") else { return nil }

        let codecsStart = codecsRange.upperBound
        guard let codecsEnd = mimeType[codecsStart...].firstIndex(of: "\"") else { return nil }

        let codecsString = mimeType[codecsStart..<codecsEnd]
        let codecs = codecsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        for codec in codecs {
            let lowercased = codec.lowercased()
            if lowercased.starts(with: "avc") {
                return "avc1"
            } else if lowercased.starts(with: "vp9") || lowercased.starts(with: "vp09") {
                return "vp9"
            } else if lowercased.starts(with: "av01") || lowercased.starts(with: "av1") {
                return "av1"
            } else if lowercased.starts(with: "hev") || lowercased.starts(with: "hvc") {
                return "hevc"
            }
        }

        return nil
    }

    private nonisolated func parseAudioCodec(from mimeType: String?) -> String? {
        guard let mimeType else { return nil }

        guard let codecsRange = mimeType.range(of: "codecs=\"") else {
            if mimeType.contains("video/mp4") {
                return "aac"
            }
            return nil
        }

        let codecsStart = codecsRange.upperBound
        guard let codecsEnd = mimeType[codecsStart...].firstIndex(of: "\"") else { return nil }

        let codecsString = mimeType[codecsStart..<codecsEnd]
        let codecs = codecsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        for codec in codecs {
            let lowercased = codec.lowercased()
            if lowercased.starts(with: "mp4a") {
                return "aac"
            } else if lowercased.contains("opus") {
                return "opus"
            } else if lowercased.contains("vorbis") {
                return "vorbis"
            }
        }

        return "aac"
    }
}

private struct YatteeAdaptiveFormat: Decodable, Sendable {
    let url: String?
    let itag: String?
    let type: String?
    let container: String?
    let encoding: String?
    let resolution: String?
    let width: Int?
    let height: Int?
    let bitrate: String?
    let clen: String?
    let fps: Int?
    let audioTrack: YatteeAudioTrack?
    let audioQuality: String?
    let httpHeaders: [String: String]?

    var isAudioOnly: Bool {
        type?.starts(with: "audio/") ?? false
    }

    nonisolated func toStream(isLive: Bool = false) -> Stream? {
        guard let urlString = url, let streamUrl = URL(string: urlString) else { return nil }

        let (language, trackName, isOriginal) = parseAudioInfo()

        let videoCodec: String? = if isAudioOnly {
            nil
        } else {
            encoding ?? parseVideoCodec(from: type)
        }

        // Prefer actual width/height from API, fallback to parsing from resolution label
        let streamResolution: StreamResolution?
        if !isAudioOnly, let w = width, let h = height, w > 0, h > 0 {
            streamResolution = StreamResolution(width: w, height: h)
        } else if !isAudioOnly {
            streamResolution = resolution.flatMap { StreamResolution(heightLabel: $0) }
        } else {
            streamResolution = nil
        }

        return Stream(
            url: streamUrl,
            resolution: streamResolution,
            format: container ?? "unknown",
            videoCodec: videoCodec,
            audioCodec: isAudioOnly ? encoding : nil,
            bitrate: bitrate.flatMap { Int($0) },
            fileSize: clen.flatMap { Int64($0) },
            isAudioOnly: isAudioOnly,
            isLive: isLive,
            mimeType: type,
            audioLanguage: language,
            audioTrackName: trackName,
            isOriginalAudio: isOriginal,
            httpHeaders: httpHeaders,
            fps: isAudioOnly ? nil : fps
        )
    }

    private nonisolated func parseVideoCodec(from mimeType: String?) -> String? {
        guard let mimeType else { return nil }

        guard let codecsRange = mimeType.range(of: "codecs=\"") else { return nil }

        let codecsStart = codecsRange.upperBound
        guard let codecsEnd = mimeType[codecsStart...].firstIndex(of: "\"") else { return nil }

        let codecsString = mimeType[codecsStart..<codecsEnd]
        let codecs = codecsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        for codec in codecs {
            let lowercased = codec.lowercased()
            if lowercased.starts(with: "avc") {
                return "avc1"
            } else if lowercased.starts(with: "vp9") || lowercased.starts(with: "vp09") {
                return "vp9"
            } else if lowercased.starts(with: "av01") || lowercased.starts(with: "av1") {
                return "av1"
            } else if lowercased.starts(with: "hev") || lowercased.starts(with: "hvc") {
                return "hevc"
            }
        }

        return nil
    }

    private nonisolated func parseAudioInfo() -> (language: String?, trackName: String?, isOriginal: Bool) {
        if let audioTrack, audioTrack.id != nil || audioTrack.displayName != nil {
            return (audioTrack.id, audioTrack.displayName, audioTrack.isDefault ?? false)
        }

        guard isAudioOnly, let urlString = url else {
            return (nil, nil, false)
        }

        guard let xtagsRange = urlString.range(of: "xtags=") else {
            return (nil, nil, false)
        }

        let xtagsStart = xtagsRange.upperBound
        let xtagsEnd = urlString[xtagsStart...].firstIndex(of: "&") ?? urlString.endIndex
        let xtagsEncoded = String(urlString[xtagsStart..<xtagsEnd])

        guard let xtags = xtagsEncoded.removingPercentEncoding else {
            return (nil, nil, false)
        }

        let pairs = xtags.split(separator: ":").reduce(into: [String: String]()) { result, pair in
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                result[String(parts[0])] = String(parts[1])
            }
        }

        guard let langCode = pairs["lang"] else {
            return (nil, nil, false)
        }

        let contentType = pairs["acont"]
        let isOriginal = contentType == "original"
        let trackName = generateTrackName(langCode: langCode, contentType: contentType)

        return (langCode, trackName, isOriginal)
    }

    private nonisolated func generateTrackName(langCode: String, contentType: String?) -> String {
        let locale = Locale(identifier: "en")
        let languageName: String

        if let name = locale.localizedString(forIdentifier: langCode) {
            languageName = name
        } else {
            let baseCode = String(langCode.split(separator: "-").first ?? Substring(langCode))
            languageName = locale.localizedString(forLanguageCode: baseCode) ?? langCode
        }

        switch contentType {
        case "original":
            return "\(languageName) (Original)"
        case "dubbed-auto":
            return "\(languageName) (Auto-dubbed)"
        case "dubbed":
            return "\(languageName) (Dubbed)"
        default:
            return languageName
        }
    }
}

private struct YatteeAudioTrack: Decodable, Sendable {
    let id: String?
    let displayName: String?
    let isDefault: Bool?
}

struct YatteeThumbnail: Decodable, Sendable {
    let quality: String?
    let url: String
    let width: Int?
    let height: Int?

    var thumbnailURL: URL? {
        if url.hasPrefix("//") {
            return URL(string: "https:" + url)
        }
        return URL(string: url)
    }

    nonisolated func toThumbnail() -> Thumbnail {
        Thumbnail(
            url: thumbnailURL ?? URL(string: "about:blank")!,
            quality: quality.map { qualityFromString($0) } ?? inferQualityFromSize(),
            width: width,
            height: height
        )
    }

    private nonisolated func qualityFromString(_ quality: String) -> Thumbnail.Quality {
        switch quality {
        case "maxres", "maxresdefault": return .maxres
        case "sddefault", "sd": return .standard
        case "high": return .high
        case "medium": return .medium
        default: return .default
        }
    }

    private nonisolated func inferQualityFromSize() -> Thumbnail.Quality {
        guard let width else { return .default }
        switch width {
        case 0..<200: return .default
        case 200..<400: return .medium
        case 400..<800: return .high
        case 800..<1200: return .standard
        default: return .maxres
        }
    }
}

private extension Array where Element == YatteeThumbnail {
    var authorThumbnailURL: URL? {
        let preferred = first { ($0.width ?? 0) >= 100 }
        return (preferred ?? last)?.thumbnailURL
    }
}

private struct YatteeChannel: Decodable, Sendable {
    let authorId: String
    let author: String
    let description: String?
    let subCount: Int?
    let totalViews: Int64?
    let authorThumbnails: [YatteeThumbnail]?
    let authorBanners: [YatteeThumbnail]?
    let authorVerified: Bool?

    nonisolated func toChannel() -> Channel {
        Channel(
            id: .global(authorId),
            name: author,
            description: description,
            subscriberCount: subCount,
            thumbnailURL: authorThumbnails?.authorThumbnailURL,
            bannerURL: authorBanners?.last?.thumbnailURL,
            isVerified: authorVerified ?? false
        )
    }
}

private struct YatteeChannelVideos: Decodable, Sendable {
    let videos: [YatteeVideo]
}

private struct YatteeChannelSearchResponse: Decodable, Sendable {
    let videos: [YatteeVideo]
}

private struct YatteeChannelVideosWithContinuation: Decodable, Sendable {
    let videos: [YatteeVideo]
    let continuation: String?
}

private struct YatteeChannelPlaylists: Decodable, Sendable {
    let playlists: [YatteeChannelPlaylistItem]
    let continuation: String?
}

private struct YatteeChannelPlaylistItem: Decodable, Sendable {
    let playlistId: String
    let title: String
    let author: String?
    let authorId: String?
    let videoCount: Int
    let playlistThumbnail: String?

    nonisolated func toPlaylist() -> Playlist {
        let thumbnailURL: URL? = playlistThumbnail.flatMap { urlString -> URL? in
            if urlString.hasPrefix("//") {
                return URL(string: "https:" + urlString)
            }
            return URL(string: urlString)
        }

        return Playlist(
            id: .global(playlistId),
            title: title,
            author: authorId.map { Author(id: $0, name: author ?? "") },
            videoCount: videoCount,
            thumbnailURL: thumbnailURL,
            videos: []
        )
    }
}

/// Item within a playlist - can be a video or a parse error.
/// The server may return `"type": "parse-error"` for videos it failed to parse.
private enum YatteePlaylistItem: Decodable, Sendable {
    case video(YatteeVideo)
    case parseError
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type)

        switch type {
        case "video", nil:
            // Videos may or may not have a type field
            do {
                self = .video(try YatteeVideo(from: decoder))
            } catch {
                self = .unknown
            }
        case "parse-error":
            self = .parseError
        default:
            self = .unknown
        }
    }
}

private struct YatteePlaylist: Decodable, Sendable {
    let playlistId: String
    let title: String
    let description: String?
    let author: String?
    let authorId: String?
    let videoCount: Int
    let videos: [YatteePlaylistItem]?

    nonisolated func toPlaylist() -> Playlist {
        // Extract only valid videos, skipping parse errors and unknown items
        let validVideos: [Video] = videos?.compactMap { item in
            if case .video(let video) = item {
                return video.toVideo()
            }
            return nil
        } ?? []

        return Playlist(
            id: .global(playlistId),
            title: title,
            description: description,
            author: authorId.map { Author(id: $0, name: author ?? "") },
            videoCount: videoCount,
            thumbnailURL: validVideos.first?.thumbnails.first?.url,
            videos: validVideos
        )
    }
}

private enum YatteeSearchItem: Decodable, Sendable {
    case video(YatteeVideo)
    case channel(YatteeSearchChannel)
    case playlist(YatteeSearchPlaylist)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "video":
            self = .video(try YatteeVideo(from: decoder))
        case "channel":
            self = .channel(try YatteeSearchChannel(from: decoder))
        case "playlist":
            self = .playlist(try YatteeSearchPlaylist(from: decoder))
        default:
            self = .unknown
        }
    }
}

private struct YatteeSearchChannel: Decodable, Sendable {
    let authorId: String
    let author: String
    let description: String?
    let subCount: Int?
    let videoCount: Int?
    let authorThumbnails: [YatteeThumbnail]?
    let authorVerified: Bool?

    nonisolated func toChannel() -> Channel {
        Channel(
            id: .global(authorId),
            name: author,
            description: description,
            subscriberCount: subCount,
            videoCount: videoCount,
            thumbnailURL: authorThumbnails?.authorThumbnailURL,
            isVerified: authorVerified ?? false
        )
    }
}

private struct YatteeSearchPlaylist: Decodable, Sendable {
    let playlistId: String
    let title: String
    let author: String?
    let authorId: String?
    let videoCount: Int
    let playlistThumbnail: String?
    let videos: [YatteeVideo]?

    nonisolated func toPlaylist() -> Playlist {
        let thumbnailURL: URL? = playlistThumbnail.flatMap { urlString -> URL? in
            if urlString.hasPrefix("//") {
                return URL(string: "https:" + urlString)
            }
            return URL(string: urlString)
        } ?? videos?.first?.videoThumbnails?.first?.thumbnailURL

        return Playlist(
            id: .global(playlistId),
            title: title,
            author: authorId.map { Author(id: $0, name: author ?? "") },
            videoCount: videoCount,
            thumbnailURL: thumbnailURL,
            videos: videos?.map { $0.toVideo() } ?? []
        )
    }
}

// MARK: - Comments Models (Invidious-compatible)

private struct YatteeComments: Decodable, Sendable {
    let comments: [YatteeComment]
    let continuation: String?
}

private struct YatteeComment: Decodable, Sendable {
    let commentId: String
    let author: String
    let authorId: String
    let authorThumbnails: [YatteeThumbnail]?
    let authorIsChannelOwner: Bool?
    let content: String
    let published: Int64?
    let publishedText: String?
    let likeCount: Int?
    let isEdited: Bool?
    let isPinned: Bool?
    let creatorHeart: YatteeCreatorHeart?
    let replies: YatteeCommentReplies?

    nonisolated func toComment() -> Comment {
        Comment(
            id: commentId,
            author: Author(
                id: authorId,
                name: author,
                thumbnailURL: authorThumbnails?.first?.thumbnailURL
            ),
            content: content,
            publishedAt: published.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            publishedText: publishedText,
            likeCount: likeCount,
            isPinned: isPinned ?? false,
            isCreatorComment: authorIsChannelOwner ?? false,
            hasCreatorHeart: creatorHeart != nil,
            replyCount: replies?.replyCount ?? 0,
            repliesContinuation: replies?.continuation
        )
    }
}

private struct YatteeCreatorHeart: Decodable, Sendable {
    let creatorThumbnail: String?
    let creatorName: String?
}

private struct YatteeCommentReplies: Decodable, Sendable {
    let replyCount: Int
    let continuation: String?
}

// MARK: - External Video Model (for non-YouTube sites)

private struct YatteeExternalVideo: Decodable, Sendable {
    let videoId: String
    let title: String
    let description: String?
    let descriptionHtml: String?
    let author: String
    let authorId: String
    let authorUrl: String?
    let authorThumbnails: [YatteeThumbnail]?
    let subCountText: String?
    let lengthSeconds: Int
    let published: Int64?
    let publishedText: String?
    let viewCount: Int?
    let likeCount: Int?
    let videoThumbnails: [YatteeThumbnail]?
    let liveNow: Bool?
    let isUpcoming: Bool?
    let premiereTimestamp: Int64?
    let hlsUrl: String?
    let dashUrl: String?
    let formatStreams: [YatteeFormatStream]?
    let adaptiveFormats: [YatteeAdaptiveFormat]?
    let captions: [YatteeCaption]?
    // External-specific fields
    let extractor: String?
    let originalUrl: String?

    /// Parses subscriber count from text like "1.78M" or "500K"
    nonisolated var subscriberCount: Int? {
        guard let text = subCountText else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespaces).uppercased()

        let multiplier: Double
        var numericPart = cleaned

        if cleaned.hasSuffix("B") {
            multiplier = 1_000_000_000
            numericPart = String(cleaned.dropLast())
        } else if cleaned.hasSuffix("M") {
            multiplier = 1_000_000
            numericPart = String(cleaned.dropLast())
        } else if cleaned.hasSuffix("K") {
            multiplier = 1_000
            numericPart = String(cleaned.dropLast())
        } else {
            multiplier = 1
        }

        guard let value = Double(numericPart) else { return nil }
        return Int(value * multiplier)
    }

    nonisolated func toVideo(originalURL: URL) -> Video {
        // Use the extractor and original URL to create an external video ID
        let extractorName = extractor ?? "unknown"
        let parsedAuthorURL = authorUrl.flatMap { URL(string: $0) }

        return Video(
            id: .extracted(videoId, extractor: extractorName, originalURL: originalURL),
            title: title,
            description: description,
            author: Author(
                id: authorId.isEmpty ? extractorName : authorId,
                name: author.isEmpty ? extractorName.capitalized : author,
                thumbnailURL: authorThumbnails?.authorThumbnailURL,
                subscriberCount: subscriberCount,
                url: parsedAuthorURL,
                hasRealChannelInfo: !authorId.isEmpty || authorUrl != nil
            ),
            duration: TimeInterval(lengthSeconds),
            publishedAt: published.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            publishedText: publishedText,
            viewCount: viewCount,
            likeCount: likeCount,
            thumbnails: videoThumbnails?.map { $0.toThumbnail() } ?? [],
            isLive: liveNow ?? false,
            isUpcoming: isUpcoming ?? false,
            scheduledStartTime: premiereTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    nonisolated func toStreams() -> [Stream] {
        var streams: [Stream] = []

        // Add HLS stream (adaptive - works for both live and on-demand content)
        if let hlsUrl, let url = URL(string: hlsUrl) {
            streams.append(Stream(
                url: url,
                resolution: nil,
                format: "hls",
                isLive: liveNow ?? false,
                mimeType: "application/x-mpegURL"
            ))
        }

        // Add DASH stream (adaptive - supports VP9, AV1, higher qualities)
        if let dashUrl, let url = URL(string: dashUrl) {
            streams.append(Stream(
                url: url,
                resolution: nil,
                format: "dash",
                isLive: liveNow ?? false,
                mimeType: "application/dash+xml"
            ))
        }

        // Add format streams (combined audio+video)
        if let formatStreams {
            streams.append(contentsOf: formatStreams.compactMap { $0.toStream(isLive: liveNow ?? false) })
        }

        // Add adaptive formats (separate audio/video)
        if let adaptiveFormats {
            streams.append(contentsOf: adaptiveFormats.compactMap { $0.toStream(isLive: liveNow ?? false) })
        }

        return streams
    }

    nonisolated func toCaptions(baseURL: URL) -> [Caption] {
        guard let captions else { return [] }
        return captions.compactMap { $0.toCaption(baseURL: baseURL) }
    }
}
