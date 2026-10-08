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

    /// Fetches one page of the credential owner's feed.
    ///
    /// Separate from the unpaged `feed(for:credential:)` because only Invidious
    /// has pages at all: Piped answers with the whole feed however it is asked,
    /// which is why it always reports there is no more to come.
    func feed(for instance: Instance, credential: String, page: Int) async throws -> FeedPage {
        switch instance.type {
        case .invidious:
            let response = try await invidiousAPI(for: instance).feed(
                instance: instance,
                sid: credential,
                page: page
            )
            return FeedPage(videos: response.videos, hasMore: response.hasMore)
        case .piped:
            let videos = try await pipedAPI(for: instance).feed(
                instance: instance,
                authToken: credential
            )
            return FeedPage(videos: videos, hasMore: false)
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

    // MARK: - Authenticated Playlists

    /// Fetches the playlists the credential's owner has on the instance.
    func userPlaylists(instance: Instance, credential: String) async throws -> [Playlist] {
        switch instance.type {
        case .invidious:
            return try await invidiousAPI(for: instance).userPlaylists(instance: instance, sid: credential)
        case .piped:
            return try await pipedAPI(for: instance).userPlaylists(instance: instance, authToken: credential)
        default:
            throw APIError.notSupported
        }
    }

    /// Fetches one of the credential owner's playlists along with the per-entry
    /// identities its rows can be removed by.
    func userPlaylistSnapshot(
        id: String,
        instance: Instance,
        credential: String
    ) async throws -> RemotePlaylistSnapshot {
        switch instance.type {
        case .invidious:
            return try await invidiousAPI(for: instance).userPlaylistSnapshot(
                id: id,
                instance: instance,
                sid: credential
            )
        case .piped:
            return try await pipedAPI(for: instance).userPlaylistSnapshot(
                id: id,
                instance: instance,
                authToken: credential
            )
        default:
            throw APIError.notSupported
        }
    }

    /// Creates a playlist for the credential's owner. **One request.**
    ///
    /// Neither backend takes a description when creating, so this does not take
    /// one either: setting it is a separate write, sequenced by the caller with
    /// a credential recheck in between.
    ///
    /// The returned playlist is the little the server says about what it just
    /// made — an id and a title. Nothing else is invented here: callers refetch
    /// the list, which is the only description that is actually the server's.
    /// - Parameters:
    ///   - privacy: Ignored by backends without a visibility concept (Piped),
    ///     and defaulted to private on those that have one when not given —
    ///     Invidious rejects a creation that carries no visibility at all.
    func createPlaylist(
        title: String,
        privacy: PlaylistPrivacy?,
        instance: Instance,
        credential: String
    ) async throws -> Playlist {
        switch instance.type {
        case .invidious:
            return try await invidiousAPI(for: instance).createPlaylist(
                title: title,
                privacy: privacy ?? .private,
                instance: instance,
                sid: credential
            )

        case .piped:
            let playlistID = try await pipedAPI(for: instance).createPlaylist(
                name: title,
                instance: instance,
                authToken: credential
            )
            return Playlist(id: .global(playlistID), title: title)

        default:
            throw APIError.notSupported
        }
    }

    /// Renames one of the credential owner's playlists. **One request.**
    ///
    /// - Parameter privacy: the visibility to store, or `nil` to leave whatever
    ///   the playlist has. Ignored on backends without a visibility concept.
    func renamePlaylist(
        id: String,
        title: String,
        privacy: PlaylistPrivacy?,
        instance: Instance,
        credential: String
    ) async throws {
        switch instance.type {
        case .invidious:
            try await invidiousAPI(for: instance).updatePlaylist(
                id: id,
                title: title,
                description: nil,
                privacy: privacy,
                instance: instance,
                sid: credential
            )

        case .piped:
            try await pipedAPI(for: instance).renamePlaylist(
                id: id,
                newName: title,
                instance: instance,
                authToken: credential
            )

        default:
            throw APIError.notSupported
        }
    }

    /// Stores a playlist's description. **One request.**
    ///
    /// - Parameter title: the playlist's title, resent unchanged. Invidious
    ///   edits every attribute through one endpoint and refuses a body without
    ///   a title; Piped has a description endpoint of its own and ignores this.
    func setPlaylistDescription(
        id: String,
        description: String,
        title: String,
        instance: Instance,
        credential: String
    ) async throws {
        switch instance.type {
        case .invidious:
            try await invidiousAPI(for: instance).updatePlaylist(
                id: id,
                title: title,
                description: description,
                privacy: nil,
                instance: instance,
                sid: credential
            )

        case .piped:
            try await pipedAPI(for: instance).updatePlaylistDescription(
                id: id,
                description: description,
                instance: instance,
                authToken: credential
            )

        default:
            throw APIError.notSupported
        }
    }

    /// Deletes one of the credential owner's playlists.
    func deletePlaylist(id: String, instance: Instance, credential: String) async throws {
        switch instance.type {
        case .invidious:
            try await invidiousAPI(for: instance).deletePlaylist(id: id, instance: instance, sid: credential)
        case .piped:
            try await pipedAPI(for: instance).deletePlaylist(id: id, instance: instance, authToken: credential)
        default:
            throw APIError.notSupported
        }
    }

    /// Appends a video to one of the credential owner's playlists.
    func addVideoToPlaylist(
        playlistID: String,
        videoID: String,
        instance: Instance,
        credential: String
    ) async throws {
        switch instance.type {
        case .invidious:
            try await invidiousAPI(for: instance).addVideoToPlaylist(
                playlistID: playlistID,
                videoID: videoID,
                instance: instance,
                sid: credential
            )
        case .piped:
            try await pipedAPI(for: instance).addToPlaylist(
                id: playlistID,
                videoID: videoID,
                instance: instance,
                authToken: credential
            )
        default:
            throw APIError.notSupported
        }
    }

    /// Removes one row from one of the credential owner's playlists.
    ///
    /// The entry id says which backend minted it, and it has to be the one this
    /// instance runs: an Invidious `indexId` means nothing to Piped, and a
    /// Piped position sent to Invidious would be a *different row* rather than
    /// an error, so a mismatch is refused rather than translated.
    func removeEntry(
        _ entryID: RemotePlaylistEntryID,
        instance: Instance,
        credential: String
    ) async throws {
        switch (entryID, instance.type) {
        case (.invidious(let playlistID, let indexID), .invidious):
            try await invidiousAPI(for: instance).removeVideoFromPlaylist(
                playlistID: playlistID,
                indexID: indexID,
                instance: instance,
                sid: credential
            )

        case (.piped(let playlistID, let position), .piped):
            try await pipedAPI(for: instance).removeFromPlaylist(
                id: playlistID,
                index: position,
                instance: instance,
                authToken: credential
            )

        case (_, .invidious), (_, .piped):
            throw APIError.invalidRequest

        default:
            throw APIError.notSupported
        }
    }

    // MARK: - Watch History

    /// One page of the credential owner's server-side watch history.
    ///
    /// Invidious is the only backend with a history endpoint at all; the
    /// capability gate above this refuses the others long before here.
    func watchHistory(
        instance: Instance,
        credential: String,
        page: Int,
        maxResults: Int
    ) async throws -> [String] {
        switch instance.type {
        case .invidious:
            return try await invidiousAPI(for: instance).watchHistory(
                instance: instance,
                sid: credential,
                page: page,
                maxResults: maxResults
            )
        default:
            throw APIError.notSupported
        }
    }

    /// Records a video as watched in the credential owner's history.
    func markWatched(videoID: String, instance: Instance, credential: String) async throws {
        switch instance.type {
        case .invidious:
            try await invidiousAPI(for: instance).markWatched(
                videoID: videoID,
                instance: instance,
                sid: credential
            )
        default:
            throw APIError.notSupported
        }
    }

    /// Removes one video from the credential owner's history.
    func removeWatched(videoID: String, instance: Instance, credential: String) async throws {
        switch instance.type {
        case .invidious:
            try await invidiousAPI(for: instance).removeWatched(
                videoID: videoID,
                instance: instance,
                sid: credential
            )
        default:
            throw APIError.notSupported
        }
    }

    // MARK: - Authentication

    /// Signs in to an instance and returns the credential its backend issues —
    /// a session id for Invidious, an auth token for Piped.
    ///
    /// Routed through here so a login carries the same per-instance
    /// configuration every other request does: the reverse-proxy basic auth, the
    /// certificate policy, and the User-Agent some instances insist on. A login
    /// that skipped any of them would fail before reaching the login endpoint.
    func login(username: String, password: String, instance: Instance) async throws -> String {
        switch instance.type {
        case .invidious:
            // Invidious' login POST runs on its own ephemeral URLSession so it
            // can read the Set-Cookie the SID arrives in, and therefore inherits
            // nothing from the client's default headers. An instance behind a
            // basic-auth proxy needs that header handed over explicitly, or the
            // proxy answers 401 before the upstream ever sees the credentials.
            var extraHeaders: [String: String]?
            if let basicAuthHeader = await basicAuthCredentialsManager?.basicAuthHeader(for: instance) {
                extraHeaders = ["Authorization": basicAuthHeader]
            }
            return try await invidiousAPI(for: instance).login(
                email: username,
                password: password,
                instance: instance,
                extraHeaders: extraHeaders
            )
        case .piped:
            // Piped's login goes through the HTTPClient, so the per-instance
            // client already carries the proxy header in its default headers.
            return try await pipedAPI(for: instance).login(
                username: username,
                password: password,
                instance: instance
            )
        default:
            // Routing, not policy: whether a backend has accounts to sign in to
            // is `InstanceType.accountCapabilities.supportsAccounts`, and a case
            // belongs here the moment that row turns true.
            throw APIError.notSupported
        }
    }

    /// Fetches streams with proxy URLs for downloads (Yattee Server: hits /proxy/fast/
    /// so the server caches the file on disk; other backends apply Invidious URL rewriting).
    func proxyStreams(videoID: String, instance: Instance) async throws -> [Stream] {
        if instance.type == .yatteeServer {
            return try await yatteeServerAPI(for: instance)
                .proxyStreams(videoID: videoID, instance: instance, mode: .download)
        }
        let fetchedStreams = try await streams(videoID: videoID, instance: instance)
        return await InvidiousAPI.proxyStreamsIfNeeded(fetchedStreams, instance: instance)
    }

    /// Fetches video details + streams for downloads. For Yattee Server this routes
    /// through `/proxy/fast/`, which caches the file on disk on the server.
    func videoWithProxyStreamsAndCaptionsAndStoryboards(id: String, instance: Instance) async throws -> (video: Video, streams: [Stream], captions: [Caption], storyboards: [Storyboard]) {
        if instance.type == .yatteeServer {
            return try await yatteeServerAPI(for: instance)
                .videoWithProxyStreamsAndCaptionsAndStoryboards(id: id, instance: instance, mode: .download)
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
            // When the user has opted into proxying for this Yattee Server source,
            // fetch playback streams through the server's /proxy/relay byte-relay
            // (Range-friendly, fast TTFB). When off, leave routing to the server's
            // per-site proxy_streaming flag — the server can still proxy by default,
            // but the client doesn't force it on top.
            if instance.proxiesVideos {
                return try await yatteeServerAPI(for: instance)
                    .videoWithProxyStreamsAndCaptionsAndStoryboards(id: id, instance: instance, mode: .relay)
            }
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
        // Keyed by link only: callers pick the Yattee Server differently, and
        // any server returns equivalent streams within the TTL.
        let key = url.absoluteString
        if let cached = recentExtractions[key], Date().timeIntervalSince(cached.date) < Self.extractionCacheTTL {
            return cached.result
        }
        let result = try await yatteeServerAPI(for: instance).extractURL(url, instance: instance)
        recentExtractions = recentExtractions.filter { Date().timeIntervalSince($0.value.date) < Self.extractionCacheTTL }
        recentExtractions[key] = (result, Date())
        return result
    }

    /// How long an extraction is reused. A link opened from Open Link is
    /// extracted to show its details page, which re-extracts for full details,
    /// and Play extracts again; all three share one Yattee Server request.
    /// Short, so a retry after a failed stream soon fetches fresh URLs.
    private static let extractionCacheTTL: TimeInterval = 60
    private var recentExtractions: [String: (result: (video: Video, streams: [Stream], captions: [Caption]), date: Date)] = [:]

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

/// The real transport behind ``AccountService``. Declared here rather than on
/// the protocol's own file so the conformance is checked next to the methods
/// that satisfy it; the protocol exists so tests can script a server.
extension ContentService: RemotePlaylistTransport {}

extension ContentService: WatchHistoryTransport {}

// MARK: - Feed Page

/// One page of an authenticated feed, with whatever the backend says about
/// there being another.
struct FeedPage: Sendable {
    let videos: [Video]
    let hasMore: Bool
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
