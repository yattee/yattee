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

    /// Credentials manager for fetching basic auth headers on demand.
    private let basicAuthCredentialsManager: BasicAuthCredentialsManager?

    init(httpClient: HTTPClient, basicAuthCredentialsManager: BasicAuthCredentialsManager? = nil) {
        // Legacy init - create factory internally
        self.httpClientFactory = HTTPClientFactory()
        self.defaultHTTPClient = httpClient
        self.defaultInvidiousAPI = InvidiousAPI(httpClient: httpClient)
        self.defaultPipedAPI = PipedAPI(httpClient: httpClient)
        self.defaultPeerTubeAPI = PeerTubeAPI(httpClient: httpClient)
        self.defaultYatteeServerAPI = YatteeServerAPI(httpClient: httpClient)
        self.basicAuthCredentialsManager = basicAuthCredentialsManager
    }

    init(httpClientFactory: HTTPClientFactory, basicAuthCredentialsManager: BasicAuthCredentialsManager? = nil) {
        self.httpClientFactory = httpClientFactory
        // Create default client for instances that don't need insecure SSL
        self.defaultHTTPClient = httpClientFactory.createClient(allowInvalidCertificates: false)
        self.defaultInvidiousAPI = InvidiousAPI(httpClient: defaultHTTPClient)
        self.defaultPipedAPI = PipedAPI(httpClient: defaultHTTPClient)
        self.defaultPeerTubeAPI = PeerTubeAPI(httpClient: defaultHTTPClient)
        self.defaultYatteeServerAPI = YatteeServerAPI(httpClient: defaultHTTPClient)
        self.basicAuthCredentialsManager = basicAuthCredentialsManager
    }

    // MARK: - Routing

    /// Builds a per-instance HTTPClient with the basic-auth `Authorization` header baked in,
    /// or returns nil if no basic-auth credentials are configured for the instance.
    /// Used to inject reverse-proxy basic auth uniformly across all backends.
    private func httpClientWithBasicAuth(for instance: Instance) async -> HTTPClient? {
        guard let authHeader = await basicAuthCredentialsManager?.basicAuthHeader(for: instance) else {
            return nil
        }
        let client = httpClientFactory.createClient(for: instance)
        await client.setDefaultHeaders(["Authorization": authHeader])
        return client
    }

    /// Returns an API client configured for the instance's SSL and auth requirements.
    private func api(for instance: Instance) async -> any InstanceAPI {
        switch instance.type {
        case .invidious:
            return await invidiousAPI(for: instance)
        case .piped:
            return await pipedAPI(for: instance)
        case .peertube:
            return await peerTubeAPI(for: instance)
        case .yatteeServer:
            return await yatteeServerAPI(for: instance)
        }
    }

    /// Returns a YatteeServerAPI configured for the instance's SSL and auth requirements.
    private func yatteeServerAPI(for instance: Instance) async -> YatteeServerAPI {
        if let authClient = await httpClientWithBasicAuth(for: instance) {
            return YatteeServerAPI(httpClient: authClient)
        }
        if !instance.allowInvalidCertificates {
            return defaultYatteeServerAPI
        }
        let insecureClient = httpClientFactory.createClient(for: instance)
        return YatteeServerAPI(httpClient: insecureClient)
    }

    /// Returns an InvidiousAPI configured for the instance's SSL and auth requirements.
    private func invidiousAPI(for instance: Instance) async -> InvidiousAPI {
        if let authClient = await httpClientWithBasicAuth(for: instance) {
            return InvidiousAPI(httpClient: authClient)
        }
        if !instance.allowInvalidCertificates {
            return defaultInvidiousAPI
        }
        let insecureClient = httpClientFactory.createClient(for: instance)
        return InvidiousAPI(httpClient: insecureClient)
    }

    /// Returns a PipedAPI configured for the instance's SSL and auth requirements.
    private func pipedAPI(for instance: Instance) async -> PipedAPI {
        if let authClient = await httpClientWithBasicAuth(for: instance) {
            return PipedAPI(httpClient: authClient)
        }
        if !instance.allowInvalidCertificates {
            return defaultPipedAPI
        }
        let insecureClient = httpClientFactory.createClient(for: instance)
        return PipedAPI(httpClient: insecureClient)
    }

    /// Returns a PeerTubeAPI configured for the instance's SSL and auth requirements.
    private func peerTubeAPI(for instance: Instance) async -> PeerTubeAPI {
        if let authClient = await httpClientWithBasicAuth(for: instance) {
            return PeerTubeAPI(httpClient: authClient)
        }
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
        let fetchedStreams = try await streams(videoID: videoID, instance: instance)
        return await InvidiousAPI.proxyStreamsIfNeeded(fetchedStreams, instance: instance)
    }

    /// Fetches video details, proxy streams, captions, and storyboards (Yattee Server only).
    /// For other backends, applies Invidious proxy rewriting if enabled.
    func videoWithProxyStreamsAndCaptionsAndStoryboards(id: String, instance: Instance) async throws -> (video: Video, streams: [Stream], captions: [Caption], storyboards: [Storyboard]) {
        if instance.type == .yatteeServer {
            return try await yatteeServerAPI(for: instance).videoWithProxyStreamsAndCaptionsAndStoryboards(id: id, instance: instance)
        }
        var result = try await videoWithStreamsAndCaptionsAndStoryboards(id: id, instance: instance)
        result.streams = await InvidiousAPI.proxyStreamsIfNeeded(result.streams, instance: instance)
        return result
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
            let pipedAPI = await pipedAPI(for: instance)
            async let videoTask = pipedAPI.video(id: id, instance: instance)
            async let streamsTask = pipedAPI.streams(videoID: id, instance: instance)
            async let captionsTask = pipedAPI.captions(videoID: id, instance: instance)

            let video = try await videoTask
            let streams = try await streamsTask
            let captions = try await captionsTask
            return (video, streams, captions, [])

        case .peertube:
            // PeerTube fallback - make separate calls (no storyboard support)
            let peerTubeAPI = await peerTubeAPI(for: instance)
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
