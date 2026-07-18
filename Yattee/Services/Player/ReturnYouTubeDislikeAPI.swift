//
//  ReturnYouTubeDislikeAPI.swift
//  Yattee
//
//  Return YouTube Dislike API client for fetching video dislikes.
//

import Foundation

/// Vote data from Return YouTube Dislike API.
struct RYDVotes: Codable, Sendable {
    let id: String
    let likes: Int
    let dislikes: Int
    let rating: Double
    let viewCount: Int
    let deleted: Bool
}

/// Return YouTube Dislike API client.
actor ReturnYouTubeDislikeAPI {
    private let httpClient: HTTPClient

    /// Cache for votes by video ID.
    private var votesCache: [String: RYDVotes] = [:]

    /// Default Return YouTube Dislike API URL.
    private static let baseURL = URL(string: "https://returnyoutubedislikeapi.com")!

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Fetches vote data for a YouTube video.
    func votes(for videoID: String) async throws -> RYDVotes {
        // Check cache first
        if let cached = votesCache[videoID] {
            return cached
        }

        var components = URLComponents(url: Self.baseURL.appendingPathComponent("/votes"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "videoId", value: videoID)
        ]

        guard let url = components.url else {
            throw APIError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let data = try await httpClient.performRaw(request)
            let decoder = JSONDecoder()
            let votes = try decoder.decode(RYDVotes.self, from: data)

            // Cache the result
            votesCache[videoID] = votes

            Task { @MainActor in
                LoggingService.shared.logPlayer("RYD: fetched votes", details: "Video: \(videoID), Dislikes: \(votes.dislikes)")
            }
            return votes
        } catch let error as DecodingError {
            Task { @MainActor in
                LoggingService.shared.logPlayerError("RYD decode error", error: error)
            }
            throw APIError.decodingError(error)
        } catch let error as APIError {
            // 404 means video not found
            if case .notFound = error {
                // Cache empty result to avoid repeated requests
                let emptyVotes = RYDVotes(id: videoID, likes: 0, dislikes: 0, rating: 0, viewCount: 0, deleted: true)
                votesCache[videoID] = emptyVotes
                return emptyVotes
            }
            throw error
        }
    }

    /// Clears the cache.
    func clearCache() {
        votesCache.removeAll()
    }
}
