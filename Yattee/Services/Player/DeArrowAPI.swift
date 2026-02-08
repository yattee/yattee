//
//  DeArrowAPI.swift
//  Yattee
//
//  DeArrow API client for fetching community-submitted titles and thumbnails.
//

import Foundation

// MARK: - Response Models

/// DeArrow branding data for a video.
struct DeArrowBranding: Codable, Sendable {
    let titles: [DeArrowTitle]
    let thumbnails: [DeArrowThumbnail]
    let randomTime: Double?
    let videoDuration: Double?

    /// Returns the best title (first non-original with positive votes, or first locked).
    var bestTitle: String? {
        // Prefer locked titles, then highest voted non-original
        if let locked = titles.first(where: { $0.locked && !$0.original }) {
            return locked.title
        }
        if let best = titles.first(where: { !$0.original && $0.votes >= 0 }) {
            return best.title
        }
        return nil
    }

    /// Returns the best thumbnail timestamp.
    var bestThumbnailTimestamp: Double? {
        // Prefer locked thumbnails, then highest voted non-original
        if let locked = thumbnails.first(where: { $0.locked && !$0.original }) {
            return locked.timestamp
        }
        if let best = thumbnails.first(where: { !$0.original && $0.votes >= 0 }) {
            return best.timestamp
        }
        // Fall back to random time if available
        return randomTime
    }
}

/// A community-submitted title.
struct DeArrowTitle: Codable, Sendable {
    let title: String
    let original: Bool
    let votes: Int
    let locked: Bool
    let UUID: String?

    enum CodingKeys: String, CodingKey {
        case title, original, votes, locked, UUID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decode(String.self, forKey: .title)
        self.original = try container.decodeIfPresent(Bool.self, forKey: .original) ?? false
        self.votes = try container.decodeIfPresent(Int.self, forKey: .votes) ?? 0
        self.locked = try container.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        self.UUID = try container.decodeIfPresent(String.self, forKey: .UUID)
    }
}

/// A community-submitted thumbnail timestamp.
struct DeArrowThumbnail: Codable, Sendable {
    let timestamp: Double?
    let original: Bool
    let votes: Int
    let locked: Bool
    let UUID: String?

    enum CodingKeys: String, CodingKey {
        case timestamp, original, votes, locked, UUID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.timestamp = try container.decodeIfPresent(Double.self, forKey: .timestamp)
        self.original = try container.decodeIfPresent(Bool.self, forKey: .original) ?? false
        self.votes = try container.decodeIfPresent(Int.self, forKey: .votes) ?? 0
        self.locked = try container.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        self.UUID = try container.decodeIfPresent(String.self, forKey: .UUID)
    }
}

// MARK: - DeArrow API

/// DeArrow API client for fetching community-submitted video branding.
actor DeArrowAPI {
    private let httpClient: HTTPClient
    private let urlSession: URLSession

    /// Cache for branding data by video ID.
    private var cache: [String: DeArrowBranding] = [:]

    /// Set of video IDs that returned 404 (no branding available).
    private var notFoundCache: Set<String> = []

    /// Maximum cache size before cleanup.
    private let maxCacheSize = 500

    /// Default DeArrow API URL.
    private static let defaultAPIURL = URL(string: "https://sponsor.ajay.app")!

    /// Default DeArrow thumbnail generation service URL.
    private static let defaultThumbnailURL = URL(string: "https://dearrow-thumb.ajay.app")!

    /// DeArrow API base URL.
    private var baseURL: URL

    /// DeArrow thumbnail generation service URL.
    private var thumbnailBaseURL: URL

    init(httpClient: HTTPClient, urlSession: URLSession = .shared, baseURL: URL? = nil, thumbnailBaseURL: URL? = nil) {
        self.httpClient = httpClient
        self.urlSession = urlSession
        self.baseURL = baseURL ?? Self.defaultAPIURL
        self.thumbnailBaseURL = thumbnailBaseURL ?? Self.defaultThumbnailURL
    }

    /// Updates the base URL for API requests.
    /// Clears the cache when URL changes.
    func setBaseURL(_ url: URL) {
        if baseURL != url {
            baseURL = url
            cache.removeAll()
            notFoundCache.removeAll()
        }
    }

    /// Updates the thumbnail base URL for thumbnail requests.
    func setThumbnailBaseURL(_ url: URL) {
        if thumbnailBaseURL != url {
            thumbnailBaseURL = url
        }
    }

    /// Returns the current thumbnail base URL.
    nonisolated func currentThumbnailBaseURL() -> URL {
        // Note: This returns the default URL when called from nonisolated context.
        // For dynamic URL access, use the async version.
        Self.defaultThumbnailURL
    }

    /// Returns the current thumbnail base URL (async version for isolation).
    func getThumbnailBaseURL() -> URL {
        thumbnailBaseURL
    }

    /// Fetches branding data for a YouTube video.
    /// - Parameter videoID: The YouTube video ID.
    /// - Returns: The branding data, or nil if not available.
    func branding(for videoID: String) async throws -> DeArrowBranding? {
        // Check not-found cache first
        if notFoundCache.contains(videoID) {
            return nil
        }

        // Check cache
        if let cached = cache[videoID] {
            return cached
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("/api/branding"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "videoID", value: videoID)
        ]

        guard let url = components.url else {
            throw APIError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5 // Short timeout for performance

        do {
            let data = try await httpClient.performRaw(request)
            let decoder = JSONDecoder()
            let branding = try decoder.decode(DeArrowBranding.self, from: data)

            // Cache the result
            cacheResult(branding, for: videoID)

            Task { @MainActor in
                LoggingService.shared.logPlayer("DeArrow: fetched branding", details: "Video: \(videoID), Title: \(branding.bestTitle ?? "none")")
            }

            return branding
        } catch let error as DecodingError {
            Task { @MainActor in
                LoggingService.shared.logPlayerError("DeArrow decode error", error: error)
            }
            throw APIError.decodingError(error)
        } catch let error as APIError {
            if case .notFound = error {
                // Cache the 404 to avoid repeated requests
                notFoundCache.insert(videoID)
                return nil
            }
            throw error
        }
    }

    /// Generates a thumbnail URL for a video at a specific timestamp.
    /// - Parameters:
    ///   - videoID: The YouTube video ID.
    ///   - timestamp: The timestamp in seconds (optional - omit for cached thumbnail).
    /// - Returns: The thumbnail URL.
    func thumbnailURL(for videoID: String, timestamp: Double? = nil) -> URL {
        var components = URLComponents(url: thumbnailBaseURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/getThumbnail"
        var queryItems = [URLQueryItem(name: "videoID", value: videoID)]
        if let timestamp {
            queryItems.append(URLQueryItem(name: "time", value: String(format: "%.2f", timestamp)))
        }
        components.queryItems = queryItems
        return components.url!
    }

    /// Generates a thumbnail URL using the default thumbnail base URL.
    /// Use this when you need a URL synchronously without actor isolation.
    nonisolated static func defaultThumbnailURL(for videoID: String, timestamp: Double? = nil) -> URL {
        var components = URLComponents(url: defaultThumbnailURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/getThumbnail"
        var queryItems = [URLQueryItem(name: "videoID", value: videoID)]
        if let timestamp {
            queryItems.append(URLQueryItem(name: "time", value: String(format: "%.2f", timestamp)))
        }
        components.queryItems = queryItems
        return components.url!
    }

    /// Result of fetching a thumbnail with timestamp verification.
    struct ThumbnailFetchResult: Sendable {
        let imageData: Data?
        let serverTimestamp: Double?
        let url: URL
    }

    /// Fetches a thumbnail, optionally without specifying time to get cached version.
    /// - Parameters:
    ///   - videoID: The YouTube video ID.
    ///   - timestamp: The timestamp in seconds (optional).
    /// - Returns: The fetch result including server's X-Timestamp header.
    func fetchThumbnail(for videoID: String, timestamp: Double? = nil) async -> ThumbnailFetchResult {
        let url = thumbnailURL(for: videoID, timestamp: timestamp)
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return ThumbnailFetchResult(imageData: nil, serverTimestamp: nil, url: url)
            }

            // Extract X-Timestamp header
            let serverTimestamp: Double?
            if let timestampHeader = httpResponse.value(forHTTPHeaderField: "X-Timestamp") {
                serverTimestamp = Double(timestampHeader)
            } else {
                serverTimestamp = nil
            }

            return ThumbnailFetchResult(imageData: data, serverTimestamp: serverTimestamp, url: url)
        } catch {
            return ThumbnailFetchResult(imageData: nil, serverTimestamp: nil, url: url)
        }
    }

    /// Clears all cached data.
    func clearCache() {
        cache.removeAll()
        notFoundCache.removeAll()
    }

    // MARK: - Private

    private func cacheResult(_ branding: DeArrowBranding, for videoID: String) {
        // Simple LRU: if cache is full, remove oldest entries
        if cache.count >= maxCacheSize {
            let keysToRemove = Array(cache.keys.prefix(maxCacheSize / 4))
            for key in keysToRemove {
                cache.removeValue(forKey: key)
            }
        }
        cache[videoID] = branding
    }
}
