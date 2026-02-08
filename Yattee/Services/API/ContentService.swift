//
//  ContentService.swift
//  Yattee
//
//  Unified interface for fetching content from any backend (Invidious, Piped, PeerTube).
//

import Foundation

/// Protocol defining the common content fetching interface.
protocol ContentServiceProtocol: Sendable {
    func trending(for instance: Instance) async throws -> [Video]
    func popular(for instance: Instance) async throws -> [Video]
    func feed(for instance: Instance, credential: String) async throws -> [Video]
    func subscriptions(for instance: Instance, credential: String) async throws -> [Channel]
    func search(query: String, instance: Instance, page: Int, filters: SearchFilters) async throws -> SearchResult
    func searchSuggestions(query: String, instance: Instance) async throws -> [String]
    func video(id: String, instance: Instance) async throws -> Video
    func channel(id: String, instance: Instance) async throws -> Channel
    func channelVideos(id: String, instance: Instance, continuation: String?) async throws -> ChannelVideosPage
    func channelPlaylists(id: String, instance: Instance, continuation: String?) async throws -> ChannelPlaylistsPage
    func channelShorts(id: String, instance: Instance, continuation: String?) async throws -> ChannelVideosPage
    func channelStreams(id: String, instance: Instance, continuation: String?) async throws -> ChannelVideosPage
    func playlist(id: String, instance: Instance) async throws -> Playlist
    func comments(videoID: String, instance: Instance, continuation: String?) async throws -> CommentsPage
    func streams(videoID: String, instance: Instance) async throws -> [Stream]
    func captions(videoID: String, instance: Instance) async throws -> [Caption]
    func channelSearch(id: String, query: String, instance: Instance, page: Int) async throws -> ChannelSearchPage
}

/// Unified content service that routes requests to the appropriate API based on instance type.
actor ContentService: ContentServiceProtocol {
    private let httpClientFactory: HTTPClientFactory

    // Default HTTPClient for instances with standard SSL (allowInvalidCertificates = false)
    private let defaultHTTPClient: HTTPClient

    // Cached API instances for default SSL mode
    private let defaultInvidiousAPI: InvidiousAPI
    private let defaultPipedAPI: PipedAPI
    private let defaultPeerTubeAPI: PeerTubeAPI
    private let defaultYatteeServerAPI: YatteeServerAPI

    /// Credentials manager for fetching Yattee Server auth headers on demand.
    private let yatteeServerCredentialsManager: YatteeServerCredentialsManager?

    init(httpClient: HTTPClient, yatteeServerCredentialsManager: YatteeServerCredentialsManager? = nil) {
        // Legacy init - create factory internally
        self.httpClientFactory = HTTPClientFactory()
        self.defaultHTTPClient = httpClient
        self.defaultInvidiousAPI = InvidiousAPI(httpClient: httpClient)
        self.defaultPipedAPI = PipedAPI(httpClient: httpClient)
        self.defaultPeerTubeAPI = PeerTubeAPI(httpClient: httpClient)
        self.defaultYatteeServerAPI = YatteeServerAPI(httpClient: httpClient)
        self.yatteeServerCredentialsManager = yatteeServerCredentialsManager
    }

    init(httpClientFactory: HTTPClientFactory, yatteeServerCredentialsManager: YatteeServerCredentialsManager? = nil) {
        self.httpClientFactory = httpClientFactory
        // Create default client for instances that don't need insecure SSL
        self.defaultHTTPClient = httpClientFactory.createClient(allowInvalidCertificates: false)
        self.defaultInvidiousAPI = InvidiousAPI(httpClient: defaultHTTPClient)
        self.defaultPipedAPI = PipedAPI(httpClient: defaultHTTPClient)
        self.defaultPeerTubeAPI = PeerTubeAPI(httpClient: defaultHTTPClient)
        self.defaultYatteeServerAPI = YatteeServerAPI(httpClient: defaultHTTPClient)
        self.yatteeServerCredentialsManager = yatteeServerCredentialsManager
    }

    // MARK: - Routing

    /// Returns an API client configured for the instance's SSL and auth requirements.
    private func api(for instance: Instance) async -> any InstanceAPI {
        // For Yattee Server, use the dedicated method that handles auth
        if instance.type == .yatteeServer {
            return await yatteeServerAPI(for: instance)
        }

        // For instances with standard SSL, use cached default API clients
        if !instance.allowInvalidCertificates {
            switch instance.type {
            case .invidious:
                return defaultInvidiousAPI
            case .piped:
                return defaultPipedAPI
            case .peertube:
                return defaultPeerTubeAPI
            case .yatteeServer:
                fatalError("Should be handled above")
            }
        }

        // For instances with allowInvalidCertificates, create API with insecure HTTPClient
        let insecureClient = httpClientFactory.createClient(for: instance)
        switch instance.type {
        case .invidious:
            return InvidiousAPI(httpClient: insecureClient)
        case .piped:
            return PipedAPI(httpClient: insecureClient)
        case .peertube:
            return PeerTubeAPI(httpClient: insecureClient)
        case .yatteeServer:
            fatalError("Should be handled above")
        }
    }

    /// Returns a YatteeServerAPI configured for the instance's SSL and auth requirements.
    private func yatteeServerAPI(for instance: Instance) async -> YatteeServerAPI {
        let api: YatteeServerAPI
        if !instance.allowInvalidCertificates {
            api = defaultYatteeServerAPI
        } else {
            let insecureClient = httpClientFactory.createClient(for: instance)
            api = YatteeServerAPI(httpClient: insecureClient)
        }

        // Fetch auth header directly from credentials manager (avoids race condition on app startup)
        let authHeader = await yatteeServerCredentialsManager?.basicAuthHeader(for: instance)
        await api.setAuthHeader(authHeader)

        return api
    }

    /// Returns an InvidiousAPI configured for the instance's SSL requirements.
    private func invidiousAPI(for instance: Instance) -> InvidiousAPI {
        if !instance.allowInvalidCertificates {
            return defaultInvidiousAPI
        }
        let insecureClient = httpClientFactory.createClient(for: instance)
        return InvidiousAPI(httpClient: insecureClient)
    }

    /// Returns a PipedAPI configured for the instance's SSL requirements.
    private func pipedAPI(for instance: Instance) -> PipedAPI {
        if !instance.allowInvalidCertificates {
            return defaultPipedAPI
        }
        let insecureClient = httpClientFactory.createClient(for: instance)
        return PipedAPI(httpClient: insecureClient)
    }

    /// Returns a PeerTubeAPI configured for the instance's SSL requirements.
    private func peerTubeAPI(for instance: Instance) -> PeerTubeAPI {
        if !instance.allowInvalidCertificates {
            return defaultPeerTubeAPI
        }
        let insecureClient = httpClientFactory.createClient(for: instance)
        return PeerTubeAPI(httpClient: insecureClient)
    }

    // MARK: - ContentServiceProtocol

    func trending(for instance: Instance) async throws -> [Video] {
        try await api(for: instance).trending(instance: instance)
    }

    func popular(for instance: Instance) async throws -> [Video] {
        try await api(for: instance).popular(instance: instance)
    }

    func feed(for instance: Instance, credential: String) async throws -> [Video] {
        switch instance.type {
        case .invidious:
            let response = try await invidiousAPI(for: instance).feed(
                instance: instance,
                sid: credential,
                page: 1,
                maxResults: 50  // Fetch 50, but HomeView will show max 15 per section
            )
            return response.videos
        case .piped:
            return try await pipedAPI(for: instance).feed(
                instance: instance,
                authToken: credential
            )
        default:
            throw APIError.notSupported
        }
    }

    func subscriptions(for instance: Instance, credential: String) async throws -> [Channel] {
        switch instance.type {
        case .invidious:
            let subs = try await invidiousAPI(for: instance).subscriptions(
                instance: instance,
                sid: credential
            )
            return subs.map { $0.toChannel(baseURL: instance.url) }
        case .piped:
            let subs = try await pipedAPI(for: instance).subscriptions(
                instance: instance,
                authToken: credential
            )
            return subs.map { $0.toChannel() }
        default:
            throw APIError.notSupported
        }
    }

    func search(query: String, instance: Instance, page: Int = 1, filters: SearchFilters = .defaults) async throws -> SearchResult {
        try await api(for: instance).search(query: query, instance: instance, page: page, filters: filters)
    }

    func searchSuggestions(query: String, instance: Instance) async throws -> [String] {
        try await api(for: instance).searchSuggestions(query: query, instance: instance)
    }

    func video(id: String, instance: Instance) async throws -> Video {
        try await api(for: instance).video(id: id, instance: instance)
    }

    func channel(id: String, instance: Instance) async throws -> Channel {
        try await api(for: instance).channel(id: id, instance: instance)
    }

    func channelVideos(id: String, instance: Instance, continuation: String? = nil) async throws -> ChannelVideosPage {
        try await api(for: instance).channelVideos(id: id, instance: instance, continuation: continuation)
    }

    func channelPlaylists(id: String, instance: Instance, continuation: String? = nil) async throws -> ChannelPlaylistsPage {
        try await api(for: instance).channelPlaylists(id: id, instance: instance, continuation: continuation)
    }

    func channelShorts(id: String, instance: Instance, continuation: String? = nil) async throws -> ChannelVideosPage {
        try await api(for: instance).channelShorts(id: id, instance: instance, continuation: continuation)
    }

    func channelStreams(id: String, instance: Instance, continuation: String? = nil) async throws -> ChannelVideosPage {
        try await api(for: instance).channelStreams(id: id, instance: instance, continuation: continuation)
    }

    func playlist(id: String, instance: Instance) async throws -> Playlist {
        try await api(for: instance).playlist(id: id, instance: instance)
    }

    func comments(videoID: String, instance: Instance, continuation: String? = nil) async throws -> CommentsPage {
        try await api(for: instance).comments(videoID: videoID, instance: instance, continuation: continuation)
    }

    func streams(videoID: String, instance: Instance) async throws -> [Stream] {
        try await api(for: instance).streams(videoID: videoID, instance: instance)
    }

    func captions(videoID: String, instance: Instance) async throws -> [Caption] {
        try await api(for: instance).captions(videoID: videoID, instance: instance)
    }

    func channelSearch(id: String, query: String, instance: Instance, page: Int = 1) async throws -> ChannelSearchPage {
        try await api(for: instance).channelSearch(id: id, query: query, instance: instance, page: page)
    }

    /// Fetches streams with proxy URLs for faster LAN downloads (Yattee Server only).
    /// For other backends, returns regular streams.
    func proxyStreams(videoID: String, instance: Instance) async throws -> [Stream] {
        if instance.type == .yatteeServer {
            return try await yatteeServerAPI(for: instance).proxyStreams(videoID: videoID, instance: instance)
        }
        return try await streams(videoID: videoID, instance: instance)
    }

    /// Fetches video details, proxy streams, captions, and storyboards (Yattee Server only).
    /// For other backends, falls back to regular streams.
    func videoWithProxyStreamsAndCaptionsAndStoryboards(id: String, instance: Instance) async throws -> (video: Video, streams: [Stream], captions: [Caption], storyboards: [Storyboard]) {
        if instance.type == .yatteeServer {
            return try await yatteeServerAPI(for: instance).videoWithProxyStreamsAndCaptionsAndStoryboards(id: id, instance: instance)
        }
        return try await videoWithStreamsAndCaptionsAndStoryboards(id: id, instance: instance)
    }

    /// Fetches video details, streams, and captions in a single API call (Invidious and Yattee Server).
    /// For other backends, falls back to separate calls.
    func videoWithStreamsAndCaptions(id: String, instance: Instance) async throws -> (video: Video, streams: [Stream], captions: [Caption]) {
        let result = try await videoWithStreamsAndCaptionsAndStoryboards(id: id, instance: instance)
        return (result.video, result.streams, result.captions)
    }

    /// Fetches video details, streams, captions, and storyboards in a single API call.
    /// Storyboards are only available for Invidious and Yattee Server instances.
    func videoWithStreamsAndCaptionsAndStoryboards(id: String, instance: Instance) async throws -> (video: Video, streams: [Stream], captions: [Caption], storyboards: [Storyboard]) {
        switch instance.type {
        case .invidious:
            return try await invidiousAPI(for: instance).videoWithStreamsAndCaptionsAndStoryboards(id: id, instance: instance)
        case .yatteeServer:
            return try await yatteeServerAPI(for: instance).videoWithStreamsAndCaptionsAndStoryboards(id: id, instance: instance)
        case .piped:
            // Piped fallback - make separate calls (no storyboard support)
            let pipedAPI = pipedAPI(for: instance)
            async let videoTask = pipedAPI.video(id: id, instance: instance)
            async let streamsTask = pipedAPI.streams(videoID: id, instance: instance)
            async let captionsTask = pipedAPI.captions(videoID: id, instance: instance)

            let video = try await videoTask
            let streams = try await streamsTask
            let captions = try await captionsTask
            return (video, streams, captions, [])

        case .peertube:
            // PeerTube fallback - make separate calls (no storyboard support)
            let peerTubeAPI = peerTubeAPI(for: instance)
            async let videoTask = peerTubeAPI.video(id: id, instance: instance)
            async let streamsTask = peerTubeAPI.streams(videoID: id, instance: instance)
            async let captionsTask = peerTubeAPI.captions(videoID: id, instance: instance)

            let video = try await videoTask
            let streams = try await streamsTask
            let captions = try await captionsTask
            return (video, streams, captions, [])
        }
    }

    // MARK: - External URL Extraction

    /// Extracts video information from any URL that yt-dlp supports.
    /// Requires a Yattee Server instance.
    ///
    /// - Parameters:
    ///   - url: The URL to extract (e.g., https://vimeo.com/12345)
    ///   - instance: A Yattee Server instance
    /// - Returns: Tuple of video, streams, and captions
    func extractURL(_ url: URL, instance: Instance) async throws -> (video: Video, streams: [Stream], captions: [Caption]) {
        guard instance.type == .yatteeServer else {
            throw APIError.notSupported
        }
        return try await yatteeServerAPI(for: instance).extractURL(url, instance: instance)
    }

    /// Extracts channel/user videos from any URL that yt-dlp supports.
    /// Requires a Yattee Server instance.
    ///
    /// This works with Vimeo, Dailymotion, SoundCloud, and many other sites.
    /// Note that some sites (like Twitter/X) may not support channel extraction.
    ///
    /// - Parameters:
    ///   - url: The channel/user URL to extract (e.g., https://vimeo.com/username)
    ///   - page: Page number (1-based)
    ///   - instance: A Yattee Server instance
    /// - Returns: Tuple of channel, videos list, and optional continuation token for next page
    func extractChannel(url: URL, page: Int = 1, instance: Instance) async throws -> (channel: Channel, videos: [Video], continuation: String?) {
        guard instance.type == .yatteeServer else {
            throw APIError.notSupported
        }
        return try await yatteeServerAPI(for: instance).extractChannel(url: url, page: page, instance: instance)
    }

    // MARK: - Yattee Server Info

    /// Fetches server info including version, dependencies, and enabled sites.
    /// Requires a Yattee Server instance.
    func yatteeServerInfo(for instance: Instance) async throws -> InstanceDetectorModels.YatteeServerFullInfo {
        guard instance.type == .yatteeServer else {
            throw APIError.notSupported
        }
        return try await yatteeServerAPI(for: instance).fetchServerInfo(for: instance)
    }
}

// MARK: - Search Result

enum OrderedSearchItem: Sendable {
    case video(Video)
    case channel(Channel)
    case playlist(Playlist)
}

struct SearchResult: Sendable {
    let videos: [Video]
    let channels: [Channel]
    let playlists: [Playlist]
    let orderedItems: [OrderedSearchItem]  // Preserves original API order
    let nextPage: Int?

    static let empty = SearchResult(videos: [], channels: [], playlists: [], orderedItems: [], nextPage: nil)
}

// MARK: - Channel Search Result

/// Item in channel search results, preserving API order for mixed video/playlist display.
enum ChannelSearchItem: Sendable, Identifiable {
    case video(Video)
    case playlist(Playlist)

    var id: String {
        switch self {
        case .video(let video): return "video-\(video.id.videoID)"
        case .playlist(let playlist): return "playlist-\(playlist.id.playlistID)"
        }
    }
}

/// Page of channel search results.
struct ChannelSearchPage: Sendable {
    let items: [ChannelSearchItem]
    let nextPage: Int?

    static let empty = ChannelSearchPage(items: [], nextPage: nil)
}
