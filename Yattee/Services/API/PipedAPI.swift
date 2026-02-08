//
//  PipedAPI.swift
//  Yattee
//
//  Piped API implementation for YouTube content.
//  API Documentation: https://docs.piped.video/docs/api-documentation/
//

@preconcurrency import Foundation

/// Piped API client for fetching YouTube content.
actor PipedAPI: InstanceAPI {
    private let httpClient: HTTPClient

    /// Cache of tab data from channel responses, keyed by channel ID.
    /// Populated when `channel()` or `channelVideos()` fetches `/channel/{id}`.
    private var channelTabsCache: [String: [PipedChannelTab]] = [:]

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    // MARK: - InstanceAPI

    func trending(instance: Instance) async throws -> [Video] {
        let endpoint = GenericEndpoint.get("/trending", query: ["region": "US"])
        let response: [PipedVideo] = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.map { $0.toVideo(instanceURL: instance.url) }
    }

    func popular(instance: Instance) async throws -> [Video] {
        // Piped doesn't have a separate popular endpoint, use trending
        try await trending(instance: instance)
    }

    func search(query: String, instance: Instance, page: Int, filters: SearchFilters) async throws -> SearchResult {
        let endpoint = GenericEndpoint.get("/search", query: [
            "q": query,
            "filter": "all"
        ])
        let response: PipedSearchResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)

        var videos: [Video] = []
        var channels: [Channel] = []
        var playlists: [Playlist] = []
        var orderedItems: [OrderedSearchItem] = []

        for item in response.items {
            switch item.type {
            case "stream":
                let video = item.toVideo(instanceURL: instance.url)
                videos.append(video)
                orderedItems.append(.video(video))
            case "channel":
                let channel = item.toChannel()
                channels.append(channel)
                orderedItems.append(.channel(channel))
            case "playlist":
                let playlist = item.toPlaylist()
                playlists.append(playlist)
                orderedItems.append(.playlist(playlist))
            default:
                break
            }
        }

        return SearchResult(
            videos: videos,
            channels: channels,
            playlists: playlists,
            orderedItems: orderedItems,
            nextPage: response.nextpage != nil ? page + 1 : nil
        )
    }

    func searchSuggestions(query: String, instance: Instance) async throws -> [String] {
        let endpoint = GenericEndpoint.get("/suggestions", query: [
            "query": query
        ])
        let response: [String] = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response
    }

    func video(id: String, instance: Instance) async throws -> Video {
        let endpoint = GenericEndpoint.get("/streams/\(id)")
        let response: PipedStreamResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.toVideo(instanceURL: instance.url, videoId: id)
    }

    func channel(id: String, instance: Instance) async throws -> Channel {
        let endpoint = GenericEndpoint.get("/channel/\(id)")
        let response: PipedChannelResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)
        if let tabs = response.tabs {
            channelTabsCache[id] = tabs
        }
        return response.toChannel()
    }

    func channelVideos(id: String, instance: Instance, continuation: String?) async throws -> ChannelVideosPage {
        if let continuation {
            // Fetch next page of channel videos
            let endpoint = GenericEndpoint.get("/nextpage/channel/\(id)", query: ["nextpage": continuation])
            let response: PipedNextPageResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)
            return ChannelVideosPage(
                videos: response.relatedStreams.map { $0.toVideo(instanceURL: instance.url) },
                continuation: response.nextpage
            )
        } else {
            // Initial fetch - get channel data (also caches tabs)
            let endpoint = GenericEndpoint.get("/channel/\(id)")
            let response: PipedChannelResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)
            if let tabs = response.tabs {
                channelTabsCache[id] = tabs
            }
            return ChannelVideosPage(
                videos: response.relatedStreams?.map { $0.toVideo(instanceURL: instance.url) } ?? [],
                continuation: response.nextpage
            )
        }
    }

    func playlist(id: String, instance: Instance) async throws -> Playlist {
        let endpoint = GenericEndpoint.get("/playlists/\(id)")
        let response: PipedPlaylistResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.toPlaylist(instanceURL: instance.url)
    }

    func comments(videoID: String, instance: Instance, continuation: String?) async throws -> CommentsPage {
        let path = continuation != nil ? "/nextpage/comments/\(videoID)" : "/comments/\(videoID)"
        var query: [String: String] = [:]
        if let continuation {
            query["nextpage"] = continuation
        }
        let endpoint = GenericEndpoint.get(path, query: query)
        let response: PipedCommentsResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)

        if response.disabled == true {
            throw APIError.commentsDisabled
        }

        return CommentsPage(
            comments: response.comments.map { $0.toComment(instanceURL: instance.url) },
            continuation: response.nextpage
        )
    }

    func streams(videoID: String, instance: Instance) async throws -> [Stream] {
        let endpoint = GenericEndpoint.get("/streams/\(videoID)")
        let response: PipedStreamResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.toStreams()
    }

    // MARK: - Channel Tabs

    func channelShorts(id: String, instance: Instance, continuation: String?) async throws -> ChannelVideosPage {
        let page = try await fetchTab(name: "shorts", channelID: id, instance: instance, continuation: continuation)
        let videos: [Video] = page.items.compactMap {
            if case .stream(let video) = $0 { return video.toVideo(instanceURL: instance.url) }
            return nil
        }
        return ChannelVideosPage(videos: videos, continuation: page.continuation)
    }

    func channelStreams(id: String, instance: Instance, continuation: String?) async throws -> ChannelVideosPage {
        let page = try await fetchTab(name: "livestreams", channelID: id, instance: instance, continuation: continuation)
        let videos: [Video] = page.items.compactMap {
            if case .stream(let video) = $0 { return video.toVideo(instanceURL: instance.url) }
            return nil
        }
        return ChannelVideosPage(videos: videos, continuation: page.continuation)
    }

    func channelPlaylists(id: String, instance: Instance, continuation: String?) async throws -> ChannelPlaylistsPage {
        let page = try await fetchTab(name: "playlists", channelID: id, instance: instance, continuation: continuation)
        let playlists: [Playlist] = page.items.compactMap {
            if case .playlist(let p) = $0 { return p.toPlaylist() }
            return nil
        }
        return ChannelPlaylistsPage(playlists: playlists, continuation: page.continuation)
    }

    // MARK: - Tab Fetching

    /// Fetches tab content for a channel, handling both initial load and pagination.
    private func fetchTab(name: String, channelID: String, instance: Instance, continuation: String?) async throws -> PipedTabPage {
        if let continuation {
            // Decode the continuation token which contains both tabData and nextpage
            let tabContinuation = try PipedTabContinuation.decode(from: continuation)
            let endpoint = GenericEndpoint.get("/channels/tabs", query: [
                "data": tabContinuation.tabData,
                "nextpage": tabContinuation.nextpage
            ])
            let response: PipedTabResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)
            let nextContinuation = response.nextpage.map {
                PipedTabContinuation(tabData: tabContinuation.tabData, nextpage: $0).encode()
            }
            return PipedTabPage(items: response.content, continuation: nextContinuation)
        } else {
            // Initial load - get tab data from cache (or fetch channel to populate it)
            var tabs = channelTabsCache[channelID]
            if tabs == nil {
                let endpoint = GenericEndpoint.get("/channel/\(channelID)")
                let response: PipedChannelResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)
                channelTabsCache[channelID] = response.tabs
                tabs = response.tabs
            }

            guard let tabData = tabs?.first(where: { $0.name == name })?.data else {
                // Tab not available for this channel
                return PipedTabPage(items: [], continuation: nil)
            }

            let endpoint = GenericEndpoint.get("/channels/tabs", query: ["data": tabData])
            let response: PipedTabResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)
            let nextContinuation = response.nextpage.map {
                PipedTabContinuation(tabData: tabData, nextpage: $0).encode()
            }
            return PipedTabPage(items: response.content, continuation: nextContinuation)
        }
    }

    // MARK: - Authentication

    /// Logs in to a Piped instance and returns the auth token.
    /// - Parameters:
    ///   - username: The user's username
    ///   - password: The user's password
    ///   - instance: The Piped instance to log in to
    /// - Returns: The auth token for subsequent authenticated requests
    func login(username: String, password: String, instance: Instance) async throws -> String {
        struct LoginRequest: Encodable, Sendable {
            let username: String
            let password: String
        }

        let body = LoginRequest(username: username, password: password)
        let endpoint = GenericEndpoint.post("/login", body: body)

        do {
            let response: PipedLoginResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)
            return response.token
        } catch let error as APIError {
            // Map HTTP 401/403 to unauthorized error
            if case .httpError(let statusCode, _) = error, statusCode == 401 || statusCode == 403 {
                throw APIError.unauthorized
            }
            throw error
        }
    }

    /// Fetches the subscription feed for a logged-in user.
    /// - Parameters:
    ///   - instance: The Piped instance
    ///   - authToken: The auth token from login
    /// - Returns: Array of videos from subscribed channels
    func feed(instance: Instance, authToken: String) async throws -> [Video] {
        // Piped feed uses authToken as a query parameter
        let endpoint = GenericEndpoint.get("/feed", query: ["authToken": authToken])
        let response: [PipedVideo] = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.map { $0.toVideo(instanceURL: instance.url) }
    }

    /// Fetches the user's subscriptions.
    /// - Parameters:
    ///   - instance: The Piped instance
    ///   - authToken: The auth token from login
    /// - Returns: Array of subscribed channels
    func subscriptions(instance: Instance, authToken: String) async throws -> [PipedSubscription] {
        // Subscriptions endpoint uses Authorization header
        let endpoint = GenericEndpoint(
            path: "/subscriptions",
            method: .get,
            headers: ["Authorization": authToken]
        )
        let response: [PipedSubscription] = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response
    }

    /// Subscribes to a channel.
    /// - Parameters:
    ///   - channelID: The YouTube channel ID to subscribe to
    ///   - instance: The Piped instance
    ///   - authToken: The auth token from login
    func subscribe(channelID: String, instance: Instance, authToken: String) async throws {
        struct SubscribeRequest: Encodable, Sendable {
            let channelId: String
        }

        let bodyData = try JSONEncoder().encode(SubscribeRequest(channelId: channelID))
        let endpoint = GenericEndpoint(
            path: "/subscribe",
            method: .post,
            headers: ["Authorization": authToken, "Content-Type": "application/json"],
            body: bodyData
        )

        // Returns {"message": "ok"} on success
        let _: PipedMessageResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)
    }

    /// Unsubscribes from a channel.
    /// - Parameters:
    ///   - channelID: The YouTube channel ID to unsubscribe from
    ///   - instance: The Piped instance
    ///   - authToken: The auth token from login
    func unsubscribe(channelID: String, instance: Instance, authToken: String) async throws {
        struct UnsubscribeRequest: Encodable, Sendable {
            let channelId: String
        }

        let bodyData = try JSONEncoder().encode(UnsubscribeRequest(channelId: channelID))
        let endpoint = GenericEndpoint(
            path: "/unsubscribe",
            method: .post,
            headers: ["Authorization": authToken, "Content-Type": "application/json"],
            body: bodyData
        )

        let _: PipedMessageResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)
    }

    /// Fetches the user's playlists.
    /// - Parameters:
    ///   - instance: The Piped instance
    ///   - authToken: The auth token from login
    /// - Returns: Array of user playlists (without videos)
    func userPlaylists(instance: Instance, authToken: String) async throws -> [Playlist] {
        let endpoint = GenericEndpoint(
            path: "/user/playlists",
            method: .get,
            headers: ["Authorization": authToken]
        )
        let response: [PipedUserPlaylist] = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.map { $0.toPlaylist() }
    }

    /// Fetches a user playlist with its videos.
    /// - Parameters:
    ///   - id: The playlist ID (UUID)
    ///   - instance: The Piped instance
    ///   - authToken: The auth token from login
    /// - Returns: Playlist with videos
    func userPlaylist(id: String, instance: Instance, authToken: String) async throws -> Playlist {
        let endpoint = GenericEndpoint(
            path: "/playlists/\(id)",
            method: .get,
            headers: ["Authorization": authToken]
        )
        let response: PipedPlaylistResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.toPlaylist(instanceURL: instance.url, playlistID: id)
    }
}

// MARK: - Piped Authentication Response Models

/// Login response from Piped API.
private struct PipedLoginResponse: Decodable, Sendable {
    let token: String
}

/// Generic message response from Piped API (used by subscribe/unsubscribe).
private struct PipedMessageResponse: Decodable, Sendable {
    let message: String
}

/// Subscription info from Piped API.
struct PipedSubscription: Decodable, Sendable {
    let url: String
    let name: String
    let avatar: String?
    let verified: Bool?

    var channelId: String {
        url.replacingOccurrences(of: "/channel/", with: "")
    }

    func toChannel() -> Channel {
        Channel(
            id: .global(channelId),
            name: name,
            thumbnailURL: avatar.flatMap { URL(string: $0) },
            isVerified: verified ?? false
        )
    }
}

// MARK: - HTML Stripping

/// Strips HTML tags from Piped descriptions, converting them to plain text.
private func stripHTML(_ html: String) -> String {
    var text = html

    // Convert <br> variants to newlines
    text = text.replacingOccurrences(
        of: "<br\\s*/?>",
        with: "\n",
        options: .regularExpression
    )

    // Extract link text from <a> tags (keep visible text, drop markup)
    text = text.replacingOccurrences(
        of: "<a[^>]*>(.*?)</a>",
        with: "$1",
        options: .regularExpression
    )

    // Strip all remaining HTML tags
    text = text.replacingOccurrences(
        of: "<[^>]+>",
        with: "",
        options: .regularExpression
    )

    // Decode common HTML entities
    text = text
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&#x27;", with: "'")
        .replacingOccurrences(of: "&apos;", with: "'")
        .replacingOccurrences(of: "&nbsp;", with: " ")

    // Trim excessive blank lines (3+ newlines → 2)
    text = text.replacingOccurrences(
        of: "\\n{3,}",
        with: "\n\n",
        options: .regularExpression
    )

    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Piped Response Models

private struct PipedVideo: Decodable, Sendable {
    let url: String
    let title: String
    let description: String?
    let uploaderName: String?
    let uploaderUrl: String?
    let uploaderAvatar: String?
    let duration: Int
    let uploaded: Int64?
    let uploadedDate: String?
    let views: Int64?
    let thumbnail: String?
    let uploaderVerified: Bool?
    let isShort: Bool?

    var videoId: String {
        url.replacingOccurrences(of: "/watch?v=", with: "")
    }

    var channelId: String? {
        uploaderUrl?.replacingOccurrences(of: "/channel/", with: "")
    }

    nonisolated func toVideo(instanceURL: URL) -> Video {
        Video(
            id: .global(videoId),
            title: title,
            description: description.map { stripHTML($0) },
            author: Author(
                id: channelId ?? "",
                name: uploaderName ?? "",
                thumbnailURL: uploaderAvatar.flatMap { URL(string: $0) }
            ),
            duration: TimeInterval(duration),
            publishedAt: uploaded.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) },
            publishedText: uploadedDate,
            viewCount: views.map { Int($0) },
            likeCount: nil,
            thumbnails: thumbnail.flatMap { URL(string: $0) }.map {
                [Thumbnail(url: $0, quality: .high)]
            } ?? [],
            isLive: duration == -1,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }
}

private struct PipedStreamResponse: Decodable, Sendable {
    let title: String
    let description: String?
    let uploader: String
    let uploaderUrl: String?
    let uploaderAvatar: String?
    let uploaderVerified: Bool?
    let uploaderSubscriberCount: Int64?
    let duration: Int
    let uploaded: Int64?
    let uploadDate: String?
    let views: Int64?
    let likes: Int64?
    let dislikes: Int64?
    let thumbnailUrl: String?
    let hls: String?
    let dash: String?
    let livestream: Bool?
    let videoStreams: [PipedVideoStream]?
    let audioStreams: [PipedAudioStream]?
    let relatedStreams: [PipedVideo]?

    var videoId: String? {
        // Extract from thumbnail URL as fallback
        guard let thumbnailUrl else { return nil }
        // Thumbnail format: https://pipedproxy.example.com/vi/VIDEO_ID/...
        let components = thumbnailUrl.components(separatedBy: "/vi/")
        guard components.count > 1 else { return nil }
        return components[1].components(separatedBy: "/").first
    }

    var channelId: String? {
        uploaderUrl?.replacingOccurrences(of: "/channel/", with: "")
    }

    nonisolated func toVideo(instanceURL: URL, videoId: String? = nil) -> Video {
        // Convert related streams, limiting to 12
        let related: [Video]? = relatedStreams?.prefix(12).map { $0.toVideo(instanceURL: instanceURL) }

        let resolvedVideoId = videoId ?? self.videoId ?? ""
        let thumbnails: [Thumbnail] = {
            if !resolvedVideoId.isEmpty,
               let url = URL(string: "https://i.ytimg.com/vi/\(resolvedVideoId)/maxresdefault.jpg") {
                return [Thumbnail(url: url, quality: .maxres)]
            }
            // Fallback to proxy URL if video ID not available
            if let proxyURL = thumbnailUrl.flatMap({ URL(string: $0) }) {
                return [Thumbnail(url: proxyURL, quality: .high)]
            }
            return []
        }()

        return Video(
            id: .global(resolvedVideoId),
            title: title,
            description: description.map { stripHTML($0) },
            author: Author(
                id: channelId ?? "",
                name: uploader,
                thumbnailURL: uploaderAvatar.flatMap { URL(string: $0) }
            ),
            duration: TimeInterval(duration),
            publishedAt: uploaded.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) },
            publishedText: uploadDate,
            viewCount: views.map { Int($0) },
            likeCount: likes.map { Int($0) },
            thumbnails: thumbnails,
            isLive: livestream ?? false,
            isUpcoming: false,
            scheduledStartTime: nil,
            relatedVideos: related
        )
    }

    nonisolated func toStreams() -> [Stream] {
        var streams: [Stream] = []

        // Add HLS stream (preferred - works for both live and on-demand content)
        if let hls, let url = URL(string: hls) {
            streams.append(Stream(
                url: url,
                resolution: nil,
                format: "hls",
                isLive: livestream ?? false,
                mimeType: "application/x-mpegURL"
            ))
        }

        // Add video streams
        if let videoStreams {
            streams.append(contentsOf: videoStreams.compactMap { $0.toStream() })
        }

        // Add audio streams
        if let audioStreams {
            streams.append(contentsOf: audioStreams.compactMap { $0.toStream() })
        }

        return streams
    }
}

private struct PipedVideoStream: Decodable, Sendable {
    let url: String
    let format: String?
    let quality: String?
    let mimeType: String?
    let codec: String?
    let videoOnly: Bool?
    let bitrate: Int?
    let width: Int?
    let height: Int?
    let contentLength: Int64?
    let fps: Int?

    nonisolated func toStream() -> Stream? {
        guard let streamUrl = URL(string: url) else { return nil }

        let resolution: StreamResolution?
        if let width, let height {
            resolution = StreamResolution(width: width, height: height)
        } else if let quality {
            resolution = StreamResolution(heightLabel: quality)
        } else {
            resolution = nil
        }

        return Stream(
            url: streamUrl,
            resolution: resolution,
            format: format ?? "unknown",
            videoCodec: codec,
            audioCodec: nil,
            bitrate: bitrate,
            fileSize: contentLength,
            isAudioOnly: false,
            mimeType: mimeType
        )
    }
}

private struct PipedAudioStream: Decodable, Sendable {
    let url: String
    let format: String?
    let quality: String?
    let mimeType: String?
    let codec: String?
    let bitrate: Int?
    let contentLength: Int64?
    let audioTrackId: String?
    let audioTrackName: String?
    let audioTrackLocale: String?
    let audioTrackType: String?

    nonisolated func toStream() -> Stream? {
        guard let streamUrl = URL(string: url) else { return nil }

        return Stream(
            url: streamUrl,
            resolution: nil,
            format: format ?? "unknown",
            videoCodec: nil,
            audioCodec: codec,
            bitrate: bitrate,
            fileSize: contentLength,
            isAudioOnly: true,
            mimeType: mimeType,
            audioLanguage: audioTrackId,
            audioTrackName: audioTrackName,
            isOriginalAudio: audioTrackType == "ORIGINAL"
        )
    }
}

private struct PipedSearchResponse: Decodable, Sendable {
    let items: [PipedSearchItem]
    let nextpage: String?
}

private struct PipedSearchItem: Decodable, Sendable {
    let type: String
    let url: String?
    let name: String?
    let title: String?
    let description: String?
    let thumbnail: String?
    let uploaderName: String?
    let uploaderUrl: String?
    let uploaderAvatar: String?
    let uploaderVerified: Bool?
    let duration: Int?
    let uploaded: Int64?
    let uploadedDate: String?
    let views: Int64?
    let videos: Int64?
    let subscribers: Int64?

    var videoId: String? {
        url?.replacingOccurrences(of: "/watch?v=", with: "")
    }

    var channelId: String? {
        url?.replacingOccurrences(of: "/channel/", with: "")
    }

    var playlistId: String? {
        url?.replacingOccurrences(of: "/playlist?list=", with: "")
    }

    nonisolated func toVideo(instanceURL: URL) -> Video {
        Video(
            id: .global(videoId ?? ""),
            title: title ?? name ?? "",
            description: description,
            author: Author(
                id: uploaderUrl?.replacingOccurrences(of: "/channel/", with: "") ?? "",
                name: uploaderName ?? "",
                thumbnailURL: uploaderAvatar.flatMap { URL(string: $0) }
            ),
            duration: TimeInterval(duration ?? 0),
            publishedAt: uploaded.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) },
            publishedText: uploadedDate,
            viewCount: views.map { Int($0) },
            likeCount: nil,
            thumbnails: thumbnail.flatMap { URL(string: $0) }.map {
                [Thumbnail(url: $0, quality: .high)]
            } ?? [],
            isLive: duration == -1,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }

    nonisolated func toChannel() -> Channel {
        Channel(
            id: .global(channelId ?? ""),
            name: name ?? "",
            description: description,
            subscriberCount: subscribers.map { Int($0) },
            videoCount: videos.map { Int($0) },
            thumbnailURL: thumbnail.flatMap { URL(string: $0) },
            isVerified: uploaderVerified ?? false
        )
    }

    nonisolated func toPlaylist() -> Playlist {
        Playlist(
            id: .global(playlistId ?? ""),
            title: name ?? "",
            author: uploaderName.map { Author(id: "", name: $0) },
            videoCount: videos.map { Int($0) } ?? 0,
            thumbnailURL: thumbnail.flatMap { URL(string: $0) }
        )
    }
}

private struct PipedChannelResponse: Decodable, Sendable {
    let id: String
    let name: String
    let description: String?
    let subscriberCount: Int64?
    let verified: Bool?
    let avatarUrl: String?
    let bannerUrl: String?
    let relatedStreams: [PipedVideo]?
    let nextpage: String?
    let tabs: [PipedChannelTab]?

    nonisolated func toChannel() -> Channel {
        Channel(
            id: .global(id),
            name: name,
            description: description,
            subscriberCount: subscriberCount.map { Int($0) },
            thumbnailURL: avatarUrl.flatMap { URL(string: $0) },
            bannerURL: bannerUrl.flatMap { URL(string: $0) },
            isVerified: verified ?? false
        )
    }
}

/// Tab entry from the Piped channel response.
/// Each tab has a name (e.g. "shorts", "livestreams", "playlists") and an opaque data string
/// that must be passed to `/channels/tabs?data=...` to fetch tab content.
private struct PipedChannelTab: Decodable, Sendable {
    let name: String
    let data: String
}

/// Response from `/nextpage/channel/{id}?nextpage=...` for paginated channel videos.
private struct PipedNextPageResponse: Decodable, Sendable {
    let relatedStreams: [PipedVideo]
    let nextpage: String?
}

/// Response from `/channels/tabs?data=...` for tab content.
private struct PipedTabResponse: Decodable, Sendable {
    let content: [PipedTabItem]
    let nextpage: String?
}

/// Item in a tab response - can be a stream (video/short/livestream) or a playlist.
private enum PipedTabItem: Decodable, Sendable {
    case stream(PipedVideo)
    case playlist(PipedTabPlaylist)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "stream":
            self = .stream(try PipedVideo(from: decoder))
        case "playlist":
            self = .playlist(try PipedTabPlaylist(from: decoder))
        default:
            self = .unknown
        }
    }
}

/// Playlist item from a channel tab response.
private struct PipedTabPlaylist: Decodable, Sendable {
    let url: String?
    let name: String?
    let thumbnail: String?
    let uploaderName: String?
    let uploaderUrl: String?
    let videos: Int64?

    var playlistId: String? {
        url?.replacingOccurrences(of: "/playlist?list=", with: "")
    }

    nonisolated func toPlaylist() -> Playlist {
        Playlist(
            id: .global(playlistId ?? ""),
            title: name ?? "",
            author: uploaderName.map { Author(id: uploaderUrl?.replacingOccurrences(of: "/channel/", with: "") ?? "", name: $0) },
            videoCount: videos.map { Int($0) } ?? 0,
            thumbnailURL: thumbnail.flatMap { URL(string: $0) }
        )
    }
}

/// Encodes tab data + nextpage token into a single continuation string for round-tripping.
private struct PipedTabContinuation {
    let tabData: String
    let nextpage: String

    func encode() -> String {
        let payload = ["t": tabData, "n": nextpage]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return Data(string.utf8).base64EncodedString()
    }

    static func decode(from continuation: String) throws -> PipedTabContinuation {
        guard let data = Data(base64Encoded: continuation),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let tabData = json["t"],
              let nextpage = json["n"] else {
            throw APIError.decodingError("Invalid tab continuation token")
        }
        return PipedTabContinuation(tabData: tabData, nextpage: nextpage)
    }
}

/// Internal result type for tab fetching.
private struct PipedTabPage {
    let items: [PipedTabItem]
    let continuation: String?
}

/// Item within a Piped playlist - gracefully handles malformed items.
private enum PipedPlaylistItem: Decodable, Sendable {
    case video(PipedVideo)
    case unknown

    init(from decoder: Decoder) throws {
        do {
            self = .video(try PipedVideo(from: decoder))
        } catch {
            self = .unknown
        }
    }
}

private struct PipedPlaylistResponse: Decodable, Sendable {
    let name: String
    let description: String?
    let uploader: String?
    let uploaderUrl: String?
    let uploaderAvatar: String?
    let videos: Int?
    let relatedStreams: [PipedPlaylistItem]?
    let thumbnailUrl: String?

    nonisolated func toPlaylist(instanceURL: URL, playlistID: String? = nil) -> Playlist {
        // Extract only valid videos, skipping malformed items
        let validVideos: [Video] = relatedStreams?.compactMap { item in
            if case .video(let video) = item {
                return video.toVideo(instanceURL: instanceURL)
            }
            return nil
        } ?? []

        return Playlist(
            id: .global(playlistID ?? UUID().uuidString),
            title: name,
            description: description,
            author: uploader.map {
                Author(
                    id: uploaderUrl?.replacingOccurrences(of: "/channel/", with: "") ?? "",
                    name: $0,
                    thumbnailURL: uploaderAvatar.flatMap { URL(string: $0) }
                )
            },
            videoCount: videos ?? validVideos.count,
            thumbnailURL: thumbnailUrl.flatMap { URL(string: $0) },
            videos: validVideos
        )
    }
}

/// User playlist from Piped `/user/playlists` endpoint.
private struct PipedUserPlaylist: Decodable, Sendable {
    let id: String
    let name: String
    let shortDescription: String?
    let thumbnail: String?
    let videos: Int?

    nonisolated func toPlaylist() -> Playlist {
        Playlist(
            id: .global(id),
            title: name,
            description: shortDescription,
            videoCount: videos ?? 0,
            thumbnailURL: thumbnail.flatMap { URL(string: $0) }
        )
    }
}

private struct PipedCommentsResponse: Decodable, Sendable {
    let comments: [PipedComment]
    let nextpage: String?
    let disabled: Bool?
    let commentCount: Int?
}

private struct PipedComment: Decodable, Sendable {
    let commentId: String
    let author: String
    let commentorUrl: String?
    let thumbnail: String?
    let commentText: String
    let commentedTime: String?
    let likeCount: Int?
    let pinned: Bool?
    let hearted: Bool?
    let creatorReplied: Bool?
    let replyCount: Int?
    let repliesPage: String?
    let channelOwner: Bool?

    nonisolated func toComment(instanceURL: URL) -> Comment {
        Comment(
            id: commentId,
            author: Author(
                id: commentorUrl?.replacingOccurrences(of: "/channel/", with: "") ?? "",
                name: author,
                thumbnailURL: thumbnail.flatMap { URL(string: $0) }
            ),
            content: stripHTML(commentText),
            publishedText: commentedTime,
            likeCount: likeCount,
            isPinned: pinned ?? false,
            isCreatorComment: channelOwner ?? false,
            hasCreatorHeart: hearted ?? false,
            replyCount: replyCount ?? 0,
            repliesContinuation: repliesPage
        )
    }
}
