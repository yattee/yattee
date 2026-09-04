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
                videos: response.relatedStreams.compactMap { item in
                    if case .video(let video) = item { return video.toVideo(instanceURL: instance.url) }
                    return nil
                },
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
                videos: response.relatedStreams?.compactMap { item in
                    if case .video(let video) = item { return video.toVideo(instanceURL: instance.url) }
                    return nil
                } ?? [],
                continuation: response.nextpage
            )
        }
    }

    func playlist(id: String, instance: Instance) async throws -> Playlist {
        let endpoint = GenericEndpoint.get("/playlists/\(id)")
        let firstResponse: PipedPlaylistResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)
        var allStreams = firstResponse.relatedStreams ?? []
        let maxPages = 50

        var nextpage = firstResponse.nextpage
        var page = 1
        while let token = nextpage, page < maxPages {
            let nextEndpoint = GenericEndpoint.get("/nextpage/playlists/\(id)", query: ["nextpage": token])
            let nextResponse: PipedPlaylistNextPageResponse = try await httpClient.fetch(nextEndpoint, baseURL: instance.url)
            let pageStreams = nextResponse.relatedStreams ?? []
            if pageStreams.isEmpty { break }
            allStreams.append(contentsOf: pageStreams)
            nextpage = nextResponse.nextpage
            page += 1
        }

        return PipedPlaylistResponse(
            name: firstResponse.name,
            description: firstResponse.description,
            uploader: firstResponse.uploader,
            uploaderUrl: firstResponse.uploaderUrl,
            uploaderAvatar: firstResponse.uploaderAvatar,
            videos: firstResponse.videos,
            relatedStreams: allStreams,
            thumbnailUrl: firstResponse.thumbnailUrl,
            nextpage: nil
        ).toPlaylist(instanceURL: instance.url)
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
        _ = try await performWrite(PipedMessageResponse.self, endpoint: endpoint, instance: instance)
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

        _ = try await performWrite(PipedMessageResponse.self, endpoint: endpoint, instance: instance)
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
        try await userPlaylistSnapshot(id: id, instance: instance, authToken: authToken).playlist
    }

    /// Fetches a user playlist along with the per-entry identities needed to
    /// mutate it.
    ///
    /// Same request as ``userPlaylist(id:instance:authToken:)`` — that one is a
    /// thin wrapper over this. Piped has no per-entry token, so entries are
    /// addressed by their position in this fetch and are only valid until the
    /// playlist next changes.
    /// - Parameters:
    ///   - id: The playlist ID (UUID)
    ///   - instance: The Piped instance
    ///   - authToken: The auth token from login
    /// - Returns: The playlist plus its addressable entries
    func userPlaylistSnapshot(id: String, instance: Instance, authToken: String) async throws -> RemotePlaylistSnapshot {
        let headers = ["Authorization": authToken]
        let firstEndpoint = GenericEndpoint(
            path: "/playlists/\(id)",
            method: .get,
            headers: headers
        )
        let firstResponse: PipedPlaylistResponse = try await httpClient.fetch(firstEndpoint, baseURL: instance.url)
        var allStreams = firstResponse.relatedStreams ?? []
        let maxPages = 50

        var nextpage = firstResponse.nextpage
        var page = 1
        while let token = nextpage, page < maxPages {
            let nextEndpoint = GenericEndpoint(
                path: "/nextpage/playlists/\(id)",
                queryItems: [URLQueryItem(name: "nextpage", value: token)],
                headers: headers
            )
            let nextResponse: PipedPlaylistNextPageResponse = try await httpClient.fetch(nextEndpoint, baseURL: instance.url)
            let pageStreams = nextResponse.relatedStreams ?? []
            if pageStreams.isEmpty { break }
            allStreams.append(contentsOf: pageStreams)
            nextpage = nextResponse.nextpage
            page += 1
        }

        return Self.buildUserPlaylistSnapshot(
            firstPage: firstResponse,
            allStreams: allStreams,
            playlistID: id,
            instanceURL: instance.url
        )
    }

    /// Builds a snapshot from an already-fetched first page plus every stream
    /// paged in after it.
    ///
    /// Pure: the network path and ``userPlaylistSnapshot(fromPageJSON:playlistID:instanceURL:)``
    /// both funnel through here, so positions are assigned in exactly one place.
    private static func buildUserPlaylistSnapshot(
        firstPage: PipedPlaylistResponse,
        allStreams: [PipedVideoItem],
        playlistID: String,
        instanceURL: URL
    ) -> RemotePlaylistSnapshot {
        let playlist = PipedPlaylistResponse(
            name: firstPage.name,
            description: firstPage.description,
            uploader: firstPage.uploader,
            uploaderUrl: firstPage.uploaderUrl,
            uploaderAvatar: firstPage.uploaderAvatar,
            videos: firstPage.videos,
            relatedStreams: allStreams,
            thumbnailUrl: firstPage.thumbnailUrl,
            nextpage: nil
        ).toPlaylist(instanceURL: instanceURL, playlistID: playlistID)

        // Positions run 0-based across every page in fetch order and are counted
        // over the *raw* stream list, malformed rows included: that is the index
        // `POST /user/playlists/remove` addresses, and renumbering over the
        // filtered display list would aim a removal one row off for every row
        // the app could not parse. `displayRow` is the separate number that says
        // where the entry appears in `playlist.videos`. Piped removes by
        // position, so these ids die with this snapshot.
        var displayRow = 0
        var entries: [RemotePlaylistEntry] = []
        for (position, item) in allStreams.enumerated() {
            guard case .video(let video) = item else { continue }
            entries.append(
                RemotePlaylistEntry(
                    id: .piped(playlistID: playlistID, position: position),
                    video: video.toVideo(instanceURL: instanceURL),
                    position: position,
                    displayRow: displayRow
                )
            )
            displayRow += 1
        }

        return RemotePlaylistSnapshot(playlist: playlist, entries: entries)
    }

    /// Runs the snapshot assembly over raw page payloads, decoding them the way
    /// the network path does. Lets the paging and position rules be exercised
    /// without a server: the first payload is a `/playlists/{id}` response,
    /// every later one a `/nextpage/playlists/{id}` response.
    static func userPlaylistSnapshot(
        fromPageJSON pages: [Data],
        playlistID: String,
        instanceURL: URL
    ) throws -> RemotePlaylistSnapshot {
        let decoder = HTTPClient.makeAPIDecoder()
        guard let firstData = pages.first else {
            throw APIError.decodingError("No playlist pages to decode")
        }

        let firstPage = try decoder.decode(PipedPlaylistResponse.self, from: firstData)
        var allStreams = firstPage.relatedStreams ?? []
        for data in pages.dropFirst() {
            let nextPage = try decoder.decode(PipedPlaylistNextPageResponse.self, from: data)
            allStreams.append(contentsOf: nextPage.relatedStreams ?? [])
        }

        return buildUserPlaylistSnapshot(
            firstPage: firstPage,
            allStreams: allStreams,
            playlistID: playlistID,
            instanceURL: instanceURL
        )
    }

    // MARK: - Playlist Management

    /// Creates a playlist owned by the logged-in user.
    ///
    /// Piped answers with `{"playlistId"}` alone — there is no privacy setting
    /// to pass and no playlist body to read back.
    /// - Parameters:
    ///   - name: The playlist name
    ///   - instance: The Piped instance
    ///   - authToken: The auth token from login
    /// - Returns: The new playlist's ID
    func createPlaylist(name: String, instance: Instance, authToken: String) async throws -> String {
        struct CreateRequest: Encodable, Sendable {
            let name: String
        }

        struct CreateResponse: Decodable, Sendable {
            let playlistId: String
        }

        let endpoint = try writeEndpoint(
            path: "/user/playlists/create",
            authToken: authToken,
            body: CreateRequest(name: name)
        )

        let response = try await performWrite(CreateResponse.self, endpoint: endpoint, instance: instance)
        return response.playlistId
    }

    /// Renames one of the user's playlists.
    /// - Parameters:
    ///   - id: The playlist ID
    ///   - newName: The name to store
    ///   - instance: The Piped instance
    ///   - authToken: The auth token from login
    func renamePlaylist(id: String, newName: String, instance: Instance, authToken: String) async throws {
        struct RenameRequest: Encodable, Sendable {
            let playlistId: String
            let newName: String
        }

        let endpoint = try writeEndpoint(
            path: "/user/playlists/rename",
            authToken: authToken,
            body: RenameRequest(playlistId: id, newName: newName)
        )

        _ = try await performWrite(PipedMessageResponse.self, endpoint: endpoint, instance: instance)
    }

    /// Replaces the description of one of the user's playlists.
    ///
    /// PATCH, unlike every other playlist write here. Upstream shipped this as
    /// `POST /user/playlists/description/change` and replaced it with
    /// `PATCH /user/playlists/description` the same afternoon, so no instance
    /// worth supporting is still on the POST spelling.
    /// - Parameters:
    ///   - id: The playlist ID
    ///   - description: The description to store
    ///   - instance: The Piped instance
    ///   - authToken: The auth token from login
    func updatePlaylistDescription(
        id: String,
        description: String,
        instance: Instance,
        authToken: String
    ) async throws {
        struct DescriptionRequest: Encodable, Sendable {
            let playlistId: String
            let description: String
        }

        let endpoint = try writeEndpoint(
            path: "/user/playlists/description",
            method: .patch,
            authToken: authToken,
            body: DescriptionRequest(playlistId: id, description: description)
        )

        _ = try await performWrite(PipedMessageResponse.self, endpoint: endpoint, instance: instance)
    }

    /// Deletes one of the user's playlists.
    /// - Parameters:
    ///   - id: The playlist ID
    ///   - instance: The Piped instance
    ///   - authToken: The auth token from login
    func deletePlaylist(id: String, instance: Instance, authToken: String) async throws {
        struct DeleteRequest: Encodable, Sendable {
            let playlistId: String
        }

        let endpoint = try writeEndpoint(
            path: "/user/playlists/delete",
            authToken: authToken,
            body: DeleteRequest(playlistId: id)
        )

        _ = try await performWrite(PipedMessageResponse.self, endpoint: endpoint, instance: instance)
    }

    /// Appends a video to one of the user's playlists.
    ///
    /// Sent as `videoIds`, the plural form. Upstream reads both spellings — the
    /// singular `videoId` is kept only for backwards compatibility, and the
    /// plural has been accepted since the batching change — so the plural is
    /// the one that will still be there.
    /// - Parameters:
    ///   - id: The playlist to add to
    ///   - videoID: The video to add
    ///   - instance: The Piped instance
    ///   - authToken: The auth token from login
    func addToPlaylist(id: String, videoID: String, instance: Instance, authToken: String) async throws {
        struct AddRequest: Encodable, Sendable {
            let playlistId: String
            let videoIds: [String]
        }

        let endpoint = try writeEndpoint(
            path: "/user/playlists/add",
            authToken: authToken,
            body: AddRequest(playlistId: id, videoIds: [videoID])
        )

        _ = try await performWrite(PipedMessageResponse.self, endpoint: endpoint, instance: instance)
    }

    /// Removes the row at a position from one of the user's playlists.
    ///
    /// Positional, because Piped offers nothing else: the index is only
    /// meaningful against the fetch it came from, and whoever calls this owes
    /// the check that the position still holds what it did. That check is
    /// deliberately not here — this layer is stateless and has no snapshot to
    /// compare against.
    /// - Parameters:
    ///   - id: The playlist to remove from
    ///   - index: Zero-based position of the row to remove
    ///   - instance: The Piped instance
    ///   - authToken: The auth token from login
    func removeFromPlaylist(id: String, index: Int, instance: Instance, authToken: String) async throws {
        struct RemoveRequest: Encodable, Sendable {
            let playlistId: String
            let index: Int
        }

        let endpoint = try writeEndpoint(
            path: "/user/playlists/remove",
            authToken: authToken,
            body: RemoveRequest(playlistId: id, index: index)
        )

        _ = try await performWrite(PipedMessageResponse.self, endpoint: endpoint, instance: instance)
    }

    /// Decodes the body of an authenticated Piped write.
    ///
    /// Piped answers a refused write with **HTTP 200** and `{"error": "..."}`:
    /// adding a video it cannot fetch — region-blocked or deleted, neither rare
    /// — and removing an index that is no longer there both come back that way,
    /// so the status code settles nothing here. Decoding straight into the
    /// success shape turns the server's own explanation into a decoding-failure
    /// message nobody can act on, so the error shape is read first: a body that
    /// carries `error` may carry `message` alongside it, and checking the
    /// success shape first would read right past the failure.
    /// - Parameters:
    ///   - type: The success shape this endpoint answers with.
    ///   - data: The raw response body.
    /// - Returns: The decoded success shape.
    /// - Throws: ``APIError/serverError(_:)`` carrying the server's message when
    ///   the body is an error body.
    static func decodeWriteResponse<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = HTTPClient.makeAPIDecoder()

        if let failure = try? decoder.decode(PipedErrorResponse.self, from: data) {
            let message = failure.error.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                throw APIError.serverError(message)
            }
        }

        do {
            return try decoder.decode(type, from: data)
        } catch let error as DecodingError {
            throw APIError.decodingError(error)
        }
    }

    /// Sends an authenticated write and reads its body the way ``decodeWriteResponse(_:from:)`` does.
    private func performWrite<T: Decodable>(
        _ type: T.Type,
        endpoint: GenericEndpoint,
        instance: Instance
    ) async throws -> T {
        let data = try await httpClient.fetchData(endpoint, baseURL: instance.url)
        return try Self.decodeWriteResponse(type, from: data)
    }

    /// Builds an authenticated JSON write request. Piped wants the token bare in
    /// `Authorization` — no `Bearer` — on every one of these.
    private nonisolated func writeEndpoint(
        path: String,
        method: HTTPMethod = .post,
        authToken: String,
        body: some Encodable
    ) throws -> GenericEndpoint {
        GenericEndpoint(
            path: path,
            method: method,
            headers: ["Authorization": authToken, "Content-Type": "application/json"],
            body: try JSONEncoder().encode(body)
        )
    }
}

// MARK: - Piped Authentication Response Models

/// Login response from Piped API.
private struct PipedLoginResponse: Decodable, Sendable {
    let token: String
}

/// Generic message response from Piped API (used by subscribe/unsubscribe and
/// every playlist write). Not private so the write-decode seam can be exercised
/// against the shape the server really answers with.
struct PipedMessageResponse: Decodable, Sendable {
    let message: String
}

/// The body Piped returns for a refused write — under HTTP 200 as often as not.
/// Some spellings carry a `message` alongside `error`, which is why this shape
/// is read before the success one.
private struct PipedErrorResponse: Decodable, Sendable {
    let error: String
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

// MARK: - Piped Sentinels

/// Piped writes `-1` where it has no value: playlist rows come back with
/// `"views": -1` and `"uploaded": -1`, and trending rows carry the same
/// sentinel. Mapped through as-is they render as "-0B views" and, once `-1`
/// milliseconds becomes a date, "56 years ago" — so a negative reading is an
/// absent one.
enum PipedSentinel {
    /// A count Piped actually has, or nil for its `-1` sentinel.
    static func count(_ raw: Int64?) -> Int? {
        guard let raw, raw >= 0 else { return nil }
        return Int(raw)
    }

    /// The upload date Piped actually has, or nil for its `-1` sentinel.
    /// Piped sends this field as epoch **milliseconds**.
    static func uploadedDate(_ raw: Int64?) -> Date? {
        guard let raw, raw >= 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(raw) / 1000)
    }
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
            publishedAt: PipedSentinel.uploadedDate(uploaded),
            publishedText: uploadedDate,
            viewCount: PipedSentinel.count(views),
            likeCount: nil,
            thumbnails: Thumbnail.fallbackChain(for: thumbnail.flatMap { URL(string: $0) }),
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
    let relatedStreams: [PipedVideoItem]?

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
        // Convert related streams, skipping malformed items, limiting to 12
        let related: [Video]? = relatedStreams?.compactMap { item -> Video? in
            if case .video(let video) = item {
                return video.toVideo(instanceURL: instanceURL)
            }
            return nil
        }.prefix(12).map { $0 }

        let resolvedVideoId = videoId ?? self.videoId ?? ""
        let thumbnails: [Thumbnail] = {
            if !resolvedVideoId.isEmpty,
               let url = URL(string: "https://i.ytimg.com/vi/\(resolvedVideoId)/maxresdefault.jpg") {
                return Thumbnail.fallbackChain(for: url)
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
            publishedAt: PipedSentinel.uploadedDate(uploaded),
            publishedText: uploadDate,
            viewCount: PipedSentinel.count(views),
            likeCount: PipedSentinel.count(likes),
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

        let audioCodec: String? = (videoOnly ?? true) ? nil : "aac"

        return Stream(
            url: streamUrl,
            resolution: resolution,
            format: format ?? "unknown",
            videoCodec: codec,
            audioCodec: audioCodec,
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
            publishedAt: PipedSentinel.uploadedDate(uploaded),
            publishedText: uploadedDate,
            viewCount: PipedSentinel.count(views),
            likeCount: nil,
            thumbnails: Thumbnail.fallbackChain(for: thumbnail.flatMap { URL(string: $0) }),
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
            subscriberCount: PipedSentinel.count(subscribers),
            videoCount: PipedSentinel.count(videos),
            thumbnailURL: thumbnail.flatMap { URL(string: $0) },
            isVerified: uploaderVerified ?? false
        )
    }

    nonisolated func toPlaylist() -> Playlist {
        Playlist(
            id: .global(playlistId ?? ""),
            title: name ?? "",
            author: uploaderName.map { Author(id: "", name: $0) },
            videoCount: PipedSentinel.count(videos) ?? 0,
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
    let relatedStreams: [PipedVideoItem]?
    let nextpage: String?
    let tabs: [PipedChannelTab]?

    nonisolated func toChannel() -> Channel {
        Channel(
            id: .global(id),
            name: name,
            description: description,
            subscriberCount: PipedSentinel.count(subscriberCount),
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
    let relatedStreams: [PipedVideoItem]
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
            videoCount: PipedSentinel.count(videos) ?? 0,
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

/// Wrapper for PipedVideo that gracefully handles malformed items.
private enum PipedVideoItem: Decodable, Sendable {
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
    /// Read as 64-bit like every other Piped count, so the `-1` sentinel goes
    /// through the same reading as the rest.
    let videos: Int64?
    let relatedStreams: [PipedVideoItem]?
    let thumbnailUrl: String?
    let nextpage: String?

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
            videoCount: PipedSentinel.count(videos) ?? validVideos.count,
            thumbnailURL: thumbnailUrl.flatMap { URL(string: $0) },
            videos: validVideos
        )
    }
}

/// Response from `/nextpage/playlists/{id}?nextpage=...` for paginated playlist videos.
private struct PipedPlaylistNextPageResponse: Decodable, Sendable {
    let relatedStreams: [PipedVideoItem]?
    let nextpage: String?
}

/// User playlist from Piped `/user/playlists` endpoint.
private struct PipedUserPlaylist: Decodable, Sendable {
    let id: String
    let name: String
    let shortDescription: String?
    let thumbnail: String?
    let videos: Int64?

    nonisolated func toPlaylist() -> Playlist {
        Playlist(
            id: .global(id),
            title: name,
            description: shortDescription,
            videoCount: PipedSentinel.count(videos) ?? 0,
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
