//
//  InvidiousAPI.swift
//  Yattee
//
//  Invidious API implementation for YouTube content.
//  API Documentation: https://docs.invidious.io/api/
//

@preconcurrency import Foundation

/// Invidious API client for fetching YouTube content.
actor InvidiousAPI: InstanceAPI {
    private let httpClient: HTTPClient

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    // MARK: - InstanceAPI

    func trending(instance: Instance) async throws -> [Video] {
        let endpoint = GenericEndpoint.get("/api/v1/trending")
        let response: [InvidiousVideo] = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.map { $0.toVideo(baseURL: instance.url) }
    }

    func popular(instance: Instance) async throws -> [Video] {
        let endpoint = GenericEndpoint.get("/api/v1/popular")
        let response: [InvidiousVideo] = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.map { $0.toVideo(baseURL: instance.url) }
    }

    func search(query: String, instance: Instance, page: Int, filters: SearchFilters = .defaults) async throws -> SearchResult {
        var queryParams: [String: String] = [
            "q": query,
            "page": String(page),
            "sort": filters.sort.rawValue,
            "type": filters.type.rawValue
        ]

        if filters.date != .any {
            queryParams["date"] = filters.date.rawValue
        }
        if filters.duration != .any {
            queryParams["duration"] = filters.duration.rawValue
        }

        let endpoint = GenericEndpoint.get("/api/v1/search", query: queryParams)
        let response: [InvidiousSearchItem] = try await httpClient.fetch(endpoint, baseURL: instance.url)

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
                        thumbnailURL: video.videoThumbnails?.first?.thumbnailURL(baseURL: instance.url)
                    )
                    playlists.append(playlist)
                    orderedItems.append(.playlist(playlist))
                } else {
                    let v = video.toVideo(baseURL: instance.url)
                    videos.append(v)
                    orderedItems.append(.video(v))
                }
            case .channel(let channel):
                let c = channel.toChannel(baseURL: instance.url)
                channels.append(c)
                orderedItems.append(.channel(c))
            case .playlist(let playlist):
                let p = playlist.toPlaylist(baseURL: instance.url)
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
        let response: InvidiousSuggestions = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.suggestions
    }

    func video(id: String, instance: Instance) async throws -> Video {
        let endpoint = GenericEndpoint.get("/api/v1/videos/\(id)")
        let response: InvidiousVideoDetails = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.toVideo(baseURL: instance.url)
    }

    func channel(id: String, instance: Instance) async throws -> Channel {
        let endpoint = GenericEndpoint.get("/api/v1/channels/\(id)")
        let response: InvidiousChannel = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.toChannel(baseURL: instance.url)
    }

    func channelVideos(id: String, instance: Instance, continuation: String?) async throws -> ChannelVideosPage {
        var query: [String: String] = [:]
        if let continuation {
            query["continuation"] = continuation
        }
        let endpoint = GenericEndpoint.get("/api/v1/channels/\(id)/videos", query: query)
        let response: InvidiousChannelVideosWithContinuation = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return ChannelVideosPage(
            videos: response.videos.map { $0.toVideo(baseURL: instance.url) },
            continuation: response.continuation
        )
    }

    func channelPlaylists(id: String, instance: Instance, continuation: String?) async throws -> ChannelPlaylistsPage {
        var query: [String: String] = [:]
        if let continuation {
            query["continuation"] = continuation
        }
        let endpoint = GenericEndpoint.get("/api/v1/channels/\(id)/playlists", query: query)
        let response: InvidiousChannelPlaylists = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return ChannelPlaylistsPage(
            playlists: response.playlists.map { $0.toPlaylist(baseURL: instance.url) },
            continuation: response.continuation
        )
    }

    func channelShorts(id: String, instance: Instance, continuation: String?) async throws -> ChannelVideosPage {
        var query: [String: String] = [:]
        if let continuation {
            query["continuation"] = continuation
        }
        let endpoint = GenericEndpoint.get("/api/v1/channels/\(id)/shorts", query: query)
        let response: InvidiousChannelVideosWithContinuation = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return ChannelVideosPage(
            videos: response.videos.map { $0.toVideo(baseURL: instance.url) },
            continuation: response.continuation
        )
    }

    func channelStreams(id: String, instance: Instance, continuation: String?) async throws -> ChannelVideosPage {
        var query: [String: String] = [:]
        if let continuation {
            query["continuation"] = continuation
        }
        let endpoint = GenericEndpoint.get("/api/v1/channels/\(id)/streams", query: query)
        let response: InvidiousChannelVideosWithContinuation = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return ChannelVideosPage(
            videos: response.videos.map { $0.toVideo(baseURL: instance.url) },
            continuation: response.continuation
        )
    }

    func playlist(id: String, instance: Instance) async throws -> Playlist {
        let firstEndpoint = GenericEndpoint.get("/api/v1/playlists/\(id)")
        let firstResponse: InvidiousPlaylist = try await httpClient.fetch(firstEndpoint, baseURL: instance.url)
        var allVideos = firstResponse.videos ?? []
        let maxPages = 50

        if firstResponse.videoCount > 0 {
            var page = 2
            while page <= maxPages {
                let endpoint = GenericEndpoint.get("/api/v1/playlists/\(id)", query: ["page": String(page)])
                let response: InvidiousPlaylist = try await httpClient.fetch(endpoint, baseURL: instance.url)
                let pageVideos = response.videos ?? []
                if pageVideos.isEmpty { break }
                allVideos.append(contentsOf: pageVideos)
                page += 1
            }
        }

        // Invidious pagination uses overlapping pages — deduplicate by playlist index
        var seenIndices = Set<Int>()
        allVideos = allVideos.filter { item in
            if case .video(let video) = item, let index = video.index {
                return seenIndices.insert(index).inserted
            }
            return true
        }

        return InvidiousPlaylist(
            playlistId: firstResponse.playlistId,
            title: firstResponse.title,
            description: firstResponse.description,
            author: firstResponse.author,
            authorId: firstResponse.authorId,
            videoCount: firstResponse.videoCount,
            videos: allVideos
        ).toPlaylist(baseURL: instance.url)
    }

    /// Fetches a user's playlist using authenticated endpoint.
    /// Required for private playlists (IVPL* IDs).
    /// - Parameters:
    ///   - id: The playlist ID
    ///   - instance: The Invidious instance
    ///   - sid: The session ID from login
    /// - Returns: The playlist with videos
    func userPlaylist(id: String, instance: Instance, sid: String) async throws -> Playlist {
        let headers = ["Cookie": "SID=\(sid)"]
        let firstEndpoint = GenericEndpoint(
            path: "/api/v1/auth/playlists/\(id)",
            queryItems: nil,
            headers: headers
        )
        let firstResponse: InvidiousPlaylist = try await httpClient.fetch(firstEndpoint, baseURL: instance.url)
        var allVideos = firstResponse.videos ?? []
        let maxPages = 50

        if firstResponse.videoCount > 0 {
            var page = 2
            while page <= maxPages {
                let endpoint = GenericEndpoint(
                    path: "/api/v1/auth/playlists/\(id)",
                    queryItems: [URLQueryItem(name: "page", value: String(page))],
                    headers: headers
                )
                let response: InvidiousPlaylist = try await httpClient.fetch(endpoint, baseURL: instance.url)
                let pageVideos = response.videos ?? []
                if pageVideos.isEmpty { break }
                allVideos.append(contentsOf: pageVideos)
                page += 1
            }
        }

        // Invidious pagination uses overlapping pages — deduplicate by playlist index
        var seenIndices = Set<Int>()
        allVideos = allVideos.filter { item in
            if case .video(let video) = item, let index = video.index {
                return seenIndices.insert(index).inserted
            }
            return true
        }

        return InvidiousPlaylist(
            playlistId: firstResponse.playlistId,
            title: firstResponse.title,
            description: firstResponse.description,
            author: firstResponse.author,
            authorId: firstResponse.authorId,
            videoCount: firstResponse.videoCount,
            videos: allVideos
        ).toPlaylist(baseURL: instance.url)
    }

    func comments(videoID: String, instance: Instance, continuation: String?) async throws -> CommentsPage {
        var query: [String: String] = [:]
        if let continuation {
            query["continuation"] = continuation
        }
        let endpoint = GenericEndpoint.get("/api/v1/comments/\(videoID)", query: query)
        do {
            let response: InvidiousComments = try await httpClient.fetch(endpoint, baseURL: instance.url)
            return CommentsPage(
                comments: response.comments.map { $0.toComment(baseURL: instance.url) },
                continuation: response.continuation
            )
        } catch APIError.notFound {
            throw APIError.commentsDisabled
        }
    }

    func streams(videoID: String, instance: Instance) async throws -> [Stream] {
        let endpoint = GenericEndpoint.get("/api/v1/videos/\(videoID)")
        let response: InvidiousVideoDetails = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.toStreams(instanceBaseURL: instance.url)
    }

    func captions(videoID: String, instance: Instance) async throws -> [Caption] {
        let endpoint = GenericEndpoint.get("/api/v1/videos/\(videoID)")
        let response: InvidiousVideoDetails = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.toCaptions(baseURL: instance.url)
    }

    func channelSearch(id: String, query: String, instance: Instance, page: Int) async throws -> ChannelSearchPage {
        let endpoint = GenericEndpoint.get("/api/v1/channels/\(id)/search", query: [
            "q": query,
            "page": String(page)
        ])
        let response: [InvidiousSearchItem] = try await httpClient.fetch(endpoint, baseURL: instance.url)

        var items: [ChannelSearchItem] = []

        for item in response {
            switch item {
            case .video(let video):
                items.append(.video(video.toVideo(baseURL: instance.url)))
            case .playlist(let playlist):
                items.append(.playlist(playlist.toPlaylist(baseURL: instance.url)))
            case .channel, .unknown:
                // Channel search only returns videos and playlists
                break
            }
        }

        // Has more pages if we got results
        let hasResults = !items.isEmpty
        return ChannelSearchPage(items: items, nextPage: hasResults ? page + 1 : nil)
    }

    /// Fetches video details, streams, and captions in a single API call.
    /// This is more efficient than calling video(), streams(), and captions() separately
    /// since they all fetch from the same endpoint.
    func videoWithStreamsAndCaptions(id: String, instance: Instance) async throws -> (video: Video, streams: [Stream], captions: [Caption]) {
        let result = try await videoWithStreamsAndCaptionsAndStoryboards(id: id, instance: instance)
        return (video: result.video, streams: result.streams, captions: result.captions)
    }

    func videoWithStreamsAndCaptionsAndStoryboards(id: String, instance: Instance) async throws -> (video: Video, streams: [Stream], captions: [Caption], storyboards: [Storyboard]) {
        let endpoint = GenericEndpoint.get("/api/v1/videos/\(id)")
        let response: InvidiousVideoDetails = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return (
            video: response.toVideo(baseURL: instance.url),
            streams: response.toStreams(instanceBaseURL: instance.url),
            captions: response.toCaptions(baseURL: instance.url),
            storyboards: response.toStoryboards(instanceBaseURL: instance.url)
        )
    }

    // MARK: - Authentication

    /// Logs in to an Invidious instance and returns the session ID (SID).
    /// - Parameters:
    ///   - email: The user's email/username
    ///   - password: The user's password
    ///   - instance: The Invidious instance to log in to
    /// - Returns: The session ID (SID) cookie value
    func login(email: String, password: String, instance: Instance, extraHeaders: [String: String]? = nil) async throws -> String {
        // Build form-urlencoded body using URLComponents for standard encoding
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "email", value: email),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "action", value: "signin")
        ]
        // URLQueryItem leaves '+' unencoded, but in form-urlencoded '+' means space
        let bodyString = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B") ?? ""

        guard let bodyData = bodyString.data(using: .utf8) else {
            throw APIError.invalidRequest
        }

        // Build the request manually to handle cookies
        var request = URLRequest(url: instance.url.appendingPathComponent("login"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        // Apply any extra headers (e.g. an HTTP Basic Auth Authorization header
        // for instances behind a reverse proxy). The login endpoint uses its own
        // URLSession below to capture Set-Cookie, so it cannot inherit headers
        // from the injected httpClient.
        if let extraHeaders {
            for (key, value) in extraHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Use a session that doesn't follow redirects so we can capture the Set-Cookie header
        let sessionConfig = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: sessionConfig, delegate: RedirectBlocker(), delegateQueue: nil)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown("Invalid response type")
        }

        // Check for successful login (302 redirect or 200 OK)
        // Invidious returns 302 on success, redirecting to home
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 302 else {
            // Check for error message in response body
            if let responseText = String(data: data, encoding: .utf8),
               responseText.contains("Wrong username") || responseText.contains("Invalid") || responseText.contains("incorrect") {
                throw APIError.unauthorized
            }
            let message = String(data: data, encoding: .utf8)
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        // Extract SID from Set-Cookie header
        // Format: "SID=<value>; domain=...; expires=...; ..."
        // HTTP/2 uses lowercase headers, so we need to check case-insensitively
        var cookieValue: String?

        // Try direct access first (works for HTTP/1.1)
        if let value = httpResponse.allHeaderFields["Set-Cookie"] as? String {
            cookieValue = value
        } else if let value = httpResponse.value(forHTTPHeaderField: "Set-Cookie") {
            cookieValue = value
        } else {
            // Iterate through all headers to find set-cookie (case-insensitive)
            for (key, value) in httpResponse.allHeaderFields {
                if let keyStr = key as? String,
                   keyStr.lowercased() == "set-cookie",
                   let valueStr = value as? String {
                    cookieValue = valueStr
                    break
                }
            }
        }

        guard let cookies = cookieValue else {
            throw APIError.unauthorized
        }

        return try extractSID(from: cookies)
    }

    /// Extracts SID from Set-Cookie header value.
    private func extractSID(from cookieHeader: String) throws -> String {
        // Look for SID= in the cookie string
        let pattern = "SID=([^;]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cookieHeader, range: NSRange(cookieHeader.startIndex..., in: cookieHeader)),
              let sidRange = Range(match.range(at: 1), in: cookieHeader) else {
            throw APIError.unauthorized
        }
        return String(cookieHeader[sidRange])
    }

    /// Fetches the subscription feed for a logged-in user.
    /// - Parameters:
    ///   - instance: The Invidious instance
    ///   - sid: The session ID from login
    ///   - page: Page number for pagination (1-based)
    ///   - maxResults: Maximum number of videos to return per page
    /// - Returns: Array of videos from subscribed channels
    func feed(instance: Instance, sid: String, page: Int = 1, maxResults: Int = 50) async throws -> InvidiousFeedResponse {
        let endpoint = GenericEndpoint.get("/api/v1/auth/feed", query: [
            "max_results": String(maxResults),
            "page": String(page)
        ])
        
        // Fetch raw data first for debugging
        let rawData = try await httpClient.fetchData(
            endpoint,
            baseURL: instance.url,
            customHeaders: ["Cookie": "SID=\(sid)"]
        )
        
        // Decode the response
        let response: InvidiousAuthFeedResponse
        do {
            response = try JSONDecoder().decode(InvidiousAuthFeedResponse.self, from: rawData)
        } catch {
            let rawString = String(data: rawData, encoding: .utf8) ?? "Unable to decode"
            LoggingService.shared.error(
                "Failed to decode Invidious feed. Raw response (first 1000 chars): \(String(rawString.prefix(1000)))",
                category: .api
            )
            throw error
        }
        
        // Combine notifications and videos arrays - Invidious returns feed items in notifications
        let allVideos = (response.notifications ?? []) + response.videos
        let videos = allVideos.map { $0.toVideo(baseURL: instance.url) }
        
        LoggingService.shared.debug(
            "Invidious feed: \(response.notifications?.count ?? 0) notifications + \(response.videos.count) videos = \(videos.count) total",
            category: .api
        )
        
        // Invidious feed doesn't provide explicit "hasMore", assume there's more until we get empty page
        return InvidiousFeedResponse(videos: videos, hasMore: !videos.isEmpty)
    }

    /// Fetches the user's subscriptions.
    /// - Parameters:
    ///   - instance: The Invidious instance
    ///   - sid: The session ID from login
    /// - Returns: Array of subscribed channels
    func subscriptions(instance: Instance, sid: String) async throws -> [InvidiousSubscription] {
        let endpoint = GenericEndpoint.get("/api/v1/auth/subscriptions")
        let response: [InvidiousSubscription] = try await httpClient.fetch(
            endpoint,
            baseURL: instance.url,
            customHeaders: ["Cookie": "SID=\(sid)"]
        )
        return response
    }

    /// Fetches the user's playlists.
    /// - Parameters:
    ///   - instance: The Invidious instance
    ///   - sid: The session ID from login
    /// - Returns: Array of user's playlists
    func userPlaylists(instance: Instance, sid: String) async throws -> [Playlist] {
        let endpoint = GenericEndpoint.get("/api/v1/auth/playlists")
        let response: [InvidiousAuthPlaylist] = try await httpClient.fetch(
            endpoint,
            baseURL: instance.url,
            customHeaders: ["Cookie": "SID=\(sid)"]
        )
        return response.map { $0.toPlaylist(baseURL: instance.url) }
    }

    // MARK: - Subscription Management

    /// Subscribes to a channel on the Invidious instance.
    /// - Parameters:
    ///   - channelID: The YouTube channel ID (UCID) to subscribe to
    ///   - instance: The Invidious instance
    ///   - sid: The session ID from login
    /// - Throws: APIError if the subscription fails
    func subscribe(to channelID: String, instance: Instance, sid: String) async throws {
        let endpoint = GenericEndpoint.post("/api/v1/auth/subscriptions/\(channelID)")
        try await httpClient.sendRequest(
            endpoint,
            baseURL: instance.url,
            customHeaders: ["Cookie": "SID=\(sid)"]
        )
    }

    /// Unsubscribes from a channel on the Invidious instance.
    /// - Parameters:
    ///   - channelID: The YouTube channel ID (UCID) to unsubscribe from
    ///   - instance: The Invidious instance
    ///   - sid: The session ID from login
    /// - Throws: APIError if the unsubscription fails
    func unsubscribe(from channelID: String, instance: Instance, sid: String) async throws {
        let endpoint = GenericEndpoint.delete("/api/v1/auth/subscriptions/\(channelID)")
        try await httpClient.sendRequest(
            endpoint,
            baseURL: instance.url,
            customHeaders: ["Cookie": "SID=\(sid)"]
        )
    }
}

// MARK: - Video Proxy

extension InvidiousAPI {
    /// Rewrites a stream URL to route through the given instance.
    /// Replaces the scheme, host, and port with the instance's, keeping the original path and query.
    static func proxiedURL(instance: Instance, originalURL: URL) -> URL {
        var components = URLComponents(url: originalURL, resolvingAgainstBaseURL: true) ?? URLComponents()
        let instanceComponents = URLComponents(url: instance.url, resolvingAgainstBaseURL: true)
        components.scheme = instanceComponents?.scheme ?? "https"
        components.host = instanceComponents?.host
        components.port = instanceComponents?.port
        return components.url ?? originalURL
    }

    /// Checks if a URL points to a YouTube CDN (googlevideo.com or youtube.com).
    /// Only these URLs should be proxied — URLs already on the instance should not be.
    static func isYouTubeCDNURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.hasSuffix("googlevideo.com") || host.hasSuffix("youtube.com")
    }

    /// Performs a HEAD request to detect if a URL returns HTTP 403 (Forbidden).
    /// Used for auto-detecting when ISPs block direct YouTube CDN access.
    static func isForbidden(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 403
            }
        } catch {
            // Network errors are not 403 — don't proxy on timeout or other failures
        }
        return false
    }

    /// Applies proxy URL rewriting to an array of streams if needed.
    /// - Parameters:
    ///   - streams: The original streams from the API
    ///   - instance: The instance to proxy through
    /// - Returns: Streams with YouTube CDN URLs rewritten to go through the instance
    static func proxyStreamsIfNeeded(_ streams: [Stream], instance: Instance) async -> [Stream] {
        guard instance.supportsVideoProxying else { return streams }

        // Find first YouTube CDN URL for 403 detection
        let firstCDNURL = streams.first(where: { isYouTubeCDNURL($0.url) })?.url

        let shouldProxy: Bool
        if instance.proxiesVideos {
            shouldProxy = true
            LoggingService.shared.info("Proxying streams through \(instance.displayName) (user-enabled)", category: .player)
        } else if let cdnURL = firstCDNURL, await isForbidden(cdnURL) {
            shouldProxy = true
            LoggingService.shared.info("Proxying streams through \(instance.displayName) (auto-detected 403)", category: .player)
        } else {
            shouldProxy = false
        }

        guard shouldProxy else { return streams }

        return streams.map { stream in
            if isYouTubeCDNURL(stream.url) {
                return stream.withURL(proxiedURL(instance: instance, originalURL: stream.url))
            }
            return stream
        }
    }
}

// MARK: - Redirect Blocker

/// URLSession delegate that prevents automatic redirect following.
/// Used for login requests where we need to capture the Set-Cookie header from the 302 response.
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Return nil to stop the redirect and capture the original response
        completionHandler(nil)
    }
}

// MARK: - Channel Tab Response Models

/// Response page for channel playlists.
struct ChannelPlaylistsPage: Sendable {
    let playlists: [Playlist]
    let continuation: String?
}

/// Response page for channel videos (shorts, streams).
struct ChannelVideosPage: Sendable {
    let videos: [Video]
    let continuation: String?
}

// MARK: - Auth Response Models

/// Response for Invidious feed endpoint.
struct InvidiousFeedResponse: Sendable {
    let videos: [Video]
    let hasMore: Bool
}

/// Subscription from Invidious auth API.
struct InvidiousSubscription: Decodable, Sendable, Identifiable {
    let author: String
    let authorId: String
    let authorThumbnails: [InvidiousSubscriptionThumbnail]?

    var id: String { authorId }

    /// Thumbnail URL for the subscription avatar.
    /// This is set externally after fetching channel details since the subscriptions API
    /// doesn't return thumbnails.
    var thumbnailURL: URL?

    enum CodingKeys: String, CodingKey {
        case author, authorId, authorThumbnails
    }
}

struct InvidiousSubscriptionThumbnail: Decodable, Sendable {
    let url: String
    let width: Int?
    let height: Int?

    func thumbnailURL(baseURL: URL) -> URL? {
        // Handle protocol-relative URLs (starting with //)
        if url.hasPrefix("//") {
            return URL(string: "https:" + url)
        }
        // Handle relative paths by resolving against baseURL
        if url.hasPrefix("/") {
            return URL(string: url, relativeTo: baseURL)?.absoluteURL
        }
        return URL(string: url)
    }
}

// MARK: - InvidiousSubscription to Channel Conversion

extension InvidiousSubscription {
    /// Converts this Invidious subscription to a Channel model for local storage.
    func toChannel(baseURL: URL) -> Channel {
        let thumbURL = thumbnailURL ?? authorThumbnails?.first?.thumbnailURL(baseURL: baseURL)
        return Channel(
            id: .global(authorId),
            name: author,
            thumbnailURL: thumbURL
        )
    }
}

/// Playlist from Invidious authenticated API (/api/v1/auth/playlists).
private struct InvidiousAuthPlaylist: Decodable, Sendable {
    let type: String?  // "invidiousPlaylist"
    let title: String
    let playlistId: String
    let author: String?
    let description: String?
    let videoCount: Int
    let updated: Int64?
    let isListed: Bool?
    let videos: [InvidiousAuthPlaylistVideo]?

    nonisolated func toPlaylist(baseURL: URL) -> Playlist {
        Playlist(
            id: .global(playlistId),
            title: title,
            description: description,
            author: author.map { Author(id: "", name: $0) },
            videoCount: videoCount,
            thumbnailURL: videos?.first?.videoThumbnails?.first?.thumbnailURL(baseURL: baseURL),
            videos: videos?.map { $0.toVideo(baseURL: baseURL) } ?? []
        )
    }
}

/// Video within an authenticated playlist response.
private struct InvidiousAuthPlaylistVideo: Decodable, Sendable {
    let title: String
    let videoId: String
    let author: String
    let authorId: String
    let authorUrl: String?
    let videoThumbnails: [InvidiousThumbnail]?
    let index: Int?
    let indexId: String?
    let lengthSeconds: Int

    nonisolated func toVideo(baseURL: URL) -> Video {
        Video(
            id: .global(videoId),
            title: title,
            description: nil,
            author: Author(id: authorId, name: author),
            duration: TimeInterval(lengthSeconds),
            publishedAt: nil,
            publishedText: nil,
            viewCount: nil,
            likeCount: nil,
            thumbnails: videoThumbnails?.map { $0.toThumbnail(baseURL: baseURL) } ?? [],
            isLive: false,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }
}

// MARK: - Invidious Response Models

/// Response from the authenticated feed endpoint.
/// The API returns an object with notifications and videos arrays.
private struct InvidiousAuthFeedResponse: Decodable, Sendable {
    let notifications: [InvidiousVideo]?
    let videos: [InvidiousVideo]
}

private struct InvidiousVideo: Decodable, Sendable {
    let videoId: String
    let index: Int?
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
    let videoThumbnails: [InvidiousThumbnail]?
    let liveNow: Bool?
    let isUpcoming: Bool?
    let premiereTimestamp: Int64?

    nonisolated func toVideo(baseURL: URL) -> Video {
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
            thumbnails: videoThumbnails?.map { $0.toThumbnail(baseURL: baseURL) } ?? [],
            isLive: liveNow ?? false,
            isUpcoming: isUpcoming ?? false,
            scheduledStartTime: premiereTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}

private struct InvidiousVideoDetails: Decodable, Sendable {
    let videoId: String
    let title: String
    let description: String?
    let descriptionHtml: String?
    let author: String
    let authorId: String
    let authorThumbnails: [InvidiousThumbnail]?
    let subCountText: String?
    let lengthSeconds: Int
    let published: Int64?
    let publishedText: String?
    let viewCount: Int?
    let likeCount: Int?
    let videoThumbnails: [InvidiousThumbnail]?
    let liveNow: Bool?
    let isUpcoming: Bool?
    let premiereTimestamp: Int64?
    let hlsUrl: String?
    let dashUrl: String?
    let formatStreams: [InvidiousFormatStream]?
    let adaptiveFormats: [InvidiousAdaptiveFormat]?
    let captions: [InvidiousCaption]?
    let storyboards: [InvidiousStoryboard]?
    let recommendedVideos: [InvidiousRecommendedVideo]?

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

    nonisolated func toVideo(baseURL: URL) -> Video {
        // Convert recommended videos, limiting to 12
        let related: [Video]? = recommendedVideos?.prefix(12).map { $0.toVideo(baseURL: baseURL) }

        return Video(
            id: .global(videoId),
            title: title,
            description: description,
            author: Author(
                id: authorId,
                name: author,
                thumbnailURL: authorThumbnails?.authorThumbnailURL(baseURL: baseURL),
                subscriberCount: subscriberCount
            ),
            duration: TimeInterval(lengthSeconds),
            publishedAt: published.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            publishedText: publishedText,
            viewCount: viewCount,
            likeCount: likeCount,
            thumbnails: videoThumbnails?.map { $0.toThumbnail(baseURL: baseURL) } ?? [],
            isLive: liveNow ?? false,
            isUpcoming: isUpcoming ?? false,
            scheduledStartTime: premiereTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            relatedVideos: related
        )
    }

    nonisolated func toStreams(instanceBaseURL: URL) -> [Stream] {
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
        // MPV can play DASH manifests directly
        if let dashUrl {
            // Resolve relative DASH URLs against instance base URL
            let resolvedDashURL: URL?
            if dashUrl.hasPrefix("/") {
                resolvedDashURL = URL(string: dashUrl, relativeTo: instanceBaseURL)?.absoluteURL
            } else {
                resolvedDashURL = URL(string: dashUrl)
            }
            if let url = resolvedDashURL {
                streams.append(Stream(
                    url: url,
                    resolution: nil,
                    format: "dash",
                    isLive: liveNow ?? false,
                    mimeType: "application/dash+xml"
                ))
            }
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

private struct InvidiousCaption: Decodable, Sendable {
    let label: String
    let languageCode: String
    let url: String

    nonisolated func toCaption(baseURL: URL) -> Caption? {
        // Prepend /companion to route through companion service
        let companionURL = "/companion" + url
        guard let fullURL = URL(string: companionURL, relativeTo: baseURL) else { return nil }
        return Caption(
            label: label,
            languageCode: languageCode,
            url: fullURL
        )
    }
}

private struct InvidiousStoryboard: Decodable, Sendable {
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

/// Recommended video from Invidious video details response.
private struct InvidiousRecommendedVideo: Decodable, Sendable {
    let videoId: String
    let title: String
    let author: String
    let authorId: String
    let authorUrl: String?
    let videoThumbnails: [InvidiousThumbnail]?
    let lengthSeconds: Int
    let viewCountText: String?
    let viewCount: Int?

    nonisolated func toVideo(baseURL: URL) -> Video {
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
            thumbnails: videoThumbnails?.map { $0.toThumbnail(baseURL: baseURL) } ?? [],
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

private struct InvidiousFormatStream: Decodable, Sendable {
    let url: String?
    let itag: String?
    let type: String?
    let quality: String?
    let container: String?
    let encoding: String?
    let resolution: String?
    let size: String?
    let fps: Int?

    nonisolated func toStream(isLive: Bool = false) -> Stream? {
        guard let urlString = url, let streamUrl = URL(string: urlString) else { return nil }

        // Parse audio codec from mimeType if present
        // Format: "video/mp4; codecs=\"avc1.42001E, mp4a.40.2\""
        let audioCodec = parseAudioCodec(from: type)

        // Extract video codec from encoding field, or fall back to parsing from type
        let videoCodec = encoding ?? parseVideoCodec(from: type)

        return Stream(
            url: streamUrl,
            resolution: resolution.flatMap { StreamResolution(heightLabel: $0) },
            format: container ?? "unknown",
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            isLive: isLive,
            mimeType: type,
            fps: fps
        )
    }

    /// Parse video codec from mimeType codecs string.
    /// Format: "video/mp4; codecs=\"avc1.42001E, mp4a.40.2\""
    private nonisolated func parseVideoCodec(from mimeType: String?) -> String? {
        guard let mimeType else { return nil }

        guard let codecsRange = mimeType.range(of: "codecs=\"") else { return nil }

        let codecsStart = codecsRange.upperBound
        guard let codecsEnd = mimeType[codecsStart...].firstIndex(of: "\"") else { return nil }

        let codecsString = mimeType[codecsStart..<codecsEnd]
        let codecs = codecsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        // Find video codec (avc1, vp9, av01, etc.)
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

    /// Parse audio codec from mimeType codecs string.
    /// Format streams always contain both video and audio.
    private nonisolated func parseAudioCodec(from mimeType: String?) -> String? {
        guard let mimeType else { return nil }

        // Look for codecs in the mimeType string
        // Example: "video/mp4; codecs=\"avc1.42001E, mp4a.40.2\""
        guard let codecsRange = mimeType.range(of: "codecs=\"") else {
            // No codecs specified, but formatStreams always have audio
            // Default to aac for mp4 container
            if mimeType.contains("video/mp4") {
                return "aac"
            }
            return nil
        }

        let codecsStart = codecsRange.upperBound
        guard let codecsEnd = mimeType[codecsStart...].firstIndex(of: "\"") else { return nil }

        let codecsString = mimeType[codecsStart..<codecsEnd]
        let codecs = codecsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        // Find audio codec (mp4a, opus, vorbis, etc.)
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

        // formatStreams are muxed, assume audio exists
        return "aac"
    }
}

private struct InvidiousAdaptiveFormat: Decodable, Sendable {
    let url: String?
    let itag: String?
    let type: String?
    let container: String?
    let encoding: String?
    let resolution: String?
    let bitrate: String?
    let clen: String?
    let audioTrack: InvidiousAudioTrack?
    let audioQuality: String?
    let fps: Int?

    var isAudioOnly: Bool {
        type?.starts(with: "audio/") ?? false
    }

    nonisolated func toStream(isLive: Bool = false) -> Stream? {
        guard let urlString = url, let streamUrl = URL(string: urlString) else { return nil }

        // Try to get audio language/track from audioTrack object first,
        // then fall back to parsing from URL xtags parameter
        let (language, trackName, isOriginal) = parseAudioInfo()

        // Extract video codec from encoding field, or fall back to parsing from type
        let videoCodec: String? = if isAudioOnly {
            nil
        } else {
            encoding ?? parseVideoCodec(from: type)
        }

        return Stream(
            url: streamUrl,
            resolution: isAudioOnly ? nil : resolution.flatMap { StreamResolution(heightLabel: $0) },
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
            fps: isAudioOnly ? nil : fps
        )
    }

    /// Parse video codec from mimeType codecs string.
    private nonisolated func parseVideoCodec(from mimeType: String?) -> String? {
        guard let mimeType else { return nil }

        guard let codecsRange = mimeType.range(of: "codecs=\"") else { return nil }

        let codecsStart = codecsRange.upperBound
        guard let codecsEnd = mimeType[codecsStart...].firstIndex(of: "\"") else { return nil }

        let codecsString = mimeType[codecsStart..<codecsEnd]
        let codecs = codecsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        // Find video codec (avc1, vp9, av01, etc.)
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

    /// Parse audio language, track name, and whether it's original from audioTrack object or URL xtags.
    /// URL xtags format: xtags=acont%3Doriginal%3Alang%3Den-US or xtags=acont%3Ddubbed-auto%3Alang%3Dde-DE
    private nonisolated func parseAudioInfo() -> (language: String?, trackName: String?, isOriginal: Bool) {
        // Prefer explicit audioTrack if available
        if let audioTrack, audioTrack.id != nil || audioTrack.displayName != nil {
            // Can't determine if original from audioTrack alone, assume not
            return (audioTrack.id, audioTrack.displayName, false)
        }

        // Parse from URL xtags parameter for audio streams
        guard isAudioOnly, let urlString = url else {
            return (nil, nil, false)
        }

        // Find xtags parameter in URL
        guard let xtagsRange = urlString.range(of: "xtags=") else {
            return (nil, nil, false)
        }

        let xtagsStart = xtagsRange.upperBound
        let xtagsEnd = urlString[xtagsStart...].firstIndex(of: "&") ?? urlString.endIndex
        let xtagsEncoded = String(urlString[xtagsStart..<xtagsEnd])

        // URL decode the xtags value
        guard let xtags = xtagsEncoded.removingPercentEncoding else {
            return (nil, nil, false)
        }

        // Parse key=value pairs separated by colons
        // Example: "acont=original:drc=1:lang=en-US" or "acont=dubbed-auto:lang=de-DE"
        let pairs = xtags.split(separator: ":").reduce(into: [String: String]()) { result, pair in
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                result[String(parts[0])] = String(parts[1])
            }
        }

        guard let langCode = pairs["lang"] else {
            return (nil, nil, false)
        }

        // Check if this is the original audio track
        let contentType = pairs["acont"]
        let isOriginal = contentType == "original"

        // Generate display name from language code and content type
        let trackName = generateTrackName(langCode: langCode, contentType: contentType)

        return (langCode, trackName, isOriginal)
    }

    /// Generate a human-readable track name from language code and content type.
    private nonisolated func generateTrackName(langCode: String, contentType: String?) -> String {
        let locale = Locale(identifier: "en")
        let languageName: String

        // Try to get language name from the code (handles both "en" and "en-US" formats)
        if let name = locale.localizedString(forIdentifier: langCode) {
            languageName = name
        } else {
            // Fall back to just the language part for codes like "en-US"
            let baseCode = String(langCode.split(separator: "-").first ?? Substring(langCode))
            languageName = locale.localizedString(forLanguageCode: baseCode) ?? langCode
        }

        // Add suffix based on content type
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

private struct InvidiousAudioTrack: Decodable, Sendable {
    let id: String?
    let displayName: String?
}

private struct InvidiousThumbnail: Decodable, Sendable {
    let quality: String?
    let url: String
    let width: Int?
    let height: Int?

    /// Resolves the thumbnail URL, handling absolute, protocol-relative, and relative paths.
    /// - Parameter baseURL: The instance base URL for resolving relative paths
    /// - Returns: The resolved absolute URL, or nil if the URL is invalid
    nonisolated func thumbnailURL(baseURL: URL) -> URL? {
        // Handle protocol-relative URLs (starting with //)
        if url.hasPrefix("//") {
            return URL(string: "https:" + url)
        }
        // Handle relative paths (starting with /)
        if url.hasPrefix("/") {
            return URL(string: url, relativeTo: baseURL)?.absoluteURL
        }
        // Absolute URL
        return URL(string: url)
    }

    nonisolated func toThumbnail(baseURL: URL) -> Thumbnail {
        Thumbnail(
            url: thumbnailURL(baseURL: baseURL) ?? URL(string: "about:blank")!,
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

private extension Array where Element == InvidiousThumbnail {
    /// Selects an appropriate author thumbnail (at least 100px for good quality on Retina displays).
    /// - Parameter baseURL: The instance base URL for resolving relative paths
    /// - Returns: The resolved thumbnail URL
    func authorThumbnailURL(baseURL: URL) -> URL? {
        // Prefer 100px or larger for good quality on Retina displays, fall back to largest available
        let preferred = first { ($0.width ?? 0) >= 100 }
        return (preferred ?? last)?.thumbnailURL(baseURL: baseURL)
    }
}

private struct InvidiousChannel: Decodable, Sendable {
    let authorId: String
    let author: String
    let description: String?
    let subCount: Int?
    let totalViews: Int64?
    let authorThumbnails: [InvidiousThumbnail]?
    let authorBanners: [InvidiousThumbnail]?
    let authorVerified: Bool?

    nonisolated func toChannel(baseURL: URL) -> Channel {
        Channel(
            id: .global(authorId),
            name: author,
            description: description,
            subscriberCount: subCount,
            thumbnailURL: authorThumbnails?.authorThumbnailURL(baseURL: baseURL),
            bannerURL: authorBanners?.last?.thumbnailURL(baseURL: baseURL),
            isVerified: authorVerified ?? false
        )
    }
}

private struct InvidiousChannelVideos: Decodable, Sendable {
    let videos: [InvidiousVideo]
}

private struct InvidiousChannelVideosWithContinuation: Decodable, Sendable {
    let videos: [InvidiousVideo]
    let continuation: String?
}

private struct InvidiousChannelPlaylists: Decodable, Sendable {
    let playlists: [InvidiousChannelPlaylistItem]
    let continuation: String?
}

private struct InvidiousChannelPlaylistItem: Decodable, Sendable {
    let playlistId: String
    let title: String
    let author: String?
    let authorId: String?
    let videoCount: Int
    let playlistThumbnail: String?

    nonisolated func toPlaylist(baseURL: URL) -> Playlist {
        // Handle protocol-relative URLs, relative paths, and absolute URLs
        let thumbnailURL: URL? = playlistThumbnail.flatMap { urlString -> URL? in
            if urlString.hasPrefix("//") {
                return URL(string: "https:" + urlString)
            } else if urlString.hasPrefix("/") {
                return URL(string: urlString, relativeTo: baseURL)?.absoluteURL
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

/// Item within a playlist - can be a video or a parse error from Invidious.
/// Invidious may return `"type": "parse-error"` for videos it failed to parse from YouTube.
private enum InvidiousPlaylistItem: Decodable, Sendable {
    case video(InvidiousVideo)
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
                self = .video(try InvidiousVideo(from: decoder))
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

private struct InvidiousPlaylist: Decodable, Sendable {
    let playlistId: String
    let title: String
    let description: String?
    let author: String?
    let authorId: String?
    let videoCount: Int
    let videos: [InvidiousPlaylistItem]?

    nonisolated func toPlaylist(baseURL: URL) -> Playlist {
        // Extract only valid videos, skipping parse errors and unknown items
        let validVideos: [Video] = videos?.compactMap { item in
            if case .video(let video) = item {
                return video.toVideo(baseURL: baseURL)
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

private struct InvidiousComments: Decodable, Sendable {
    let comments: [InvidiousComment]
    let continuation: String?
}

private struct InvidiousComment: Decodable, Sendable {
    let commentId: String
    let author: String
    let authorId: String
    let authorThumbnails: [InvidiousThumbnail]?
    let authorIsChannelOwner: Bool?
    let content: String
    let published: Int64?
    let publishedText: String?
    let likeCount: Int?
    let isEdited: Bool?
    let isPinned: Bool?
    let creatorHeart: InvidiousCreatorHeart?
    let replies: InvidiousCommentReplies?

    nonisolated func toComment(baseURL: URL) -> Comment {
        Comment(
            id: commentId,
            author: Author(
                id: authorId,
                name: author,
                thumbnailURL: authorThumbnails?.first?.thumbnailURL(baseURL: baseURL)
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

private struct InvidiousCreatorHeart: Decodable, Sendable {
    let creatorThumbnail: String?
    let creatorName: String?
}

private struct InvidiousCommentReplies: Decodable, Sendable {
    let replyCount: Int
    let continuation: String?
}

private enum InvidiousSearchItem: Decodable, Sendable {
    case video(InvidiousVideo)
    case channel(InvidiousSearchChannel)
    case playlist(InvidiousSearchPlaylist)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "video":
            self = .video(try InvidiousVideo(from: decoder))
        case "channel":
            self = .channel(try InvidiousSearchChannel(from: decoder))
        case "playlist":
            self = .playlist(try InvidiousSearchPlaylist(from: decoder))
        default:
            self = .unknown
        }
    }
}

private struct InvidiousSearchChannel: Decodable, Sendable {
    let authorId: String
    let author: String
    let description: String?
    let subCount: Int?
    let videoCount: Int?
    let authorThumbnails: [InvidiousThumbnail]?
    let authorVerified: Bool?

    nonisolated func toChannel(baseURL: URL) -> Channel {
        Channel(
            id: .global(authorId),
            name: author,
            description: description,
            subscriberCount: subCount,
            videoCount: videoCount,
            thumbnailURL: authorThumbnails?.authorThumbnailURL(baseURL: baseURL),
            isVerified: authorVerified ?? false
        )
    }
}

private struct InvidiousSearchPlaylist: Decodable, Sendable {
    let playlistId: String
    let title: String
    let author: String?
    let authorId: String?
    let videoCount: Int
    let playlistThumbnail: String?
    let videos: [InvidiousVideo]?

    nonisolated func toPlaylist(baseURL: URL) -> Playlist {
        // Use playlistThumbnail from search results, fall back to first video thumbnail
        // Handle protocol-relative URLs, relative paths, and absolute URLs
        let thumbnailURL: URL? = playlistThumbnail.flatMap { urlString -> URL? in
            if urlString.hasPrefix("//") {
                return URL(string: "https:" + urlString)
            } else if urlString.hasPrefix("/") {
                return URL(string: urlString, relativeTo: baseURL)?.absoluteURL
            }
            return URL(string: urlString)
        } ?? videos?.first?.videoThumbnails?.first?.thumbnailURL(baseURL: baseURL)

        return Playlist(
            id: .global(playlistId),
            title: title,
            author: authorId.map { Author(id: $0, name: author ?? "") },
            videoCount: videoCount,
            thumbnailURL: thumbnailURL,
            videos: videos?.map { $0.toVideo(baseURL: baseURL) } ?? []
        )
    }
}

private struct InvidiousSuggestions: Decodable, Sendable {
    let query: String
    let suggestions: [String]
}
