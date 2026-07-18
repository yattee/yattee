//
//  PeerTubeDirectoryAPI.swift
//  Yattee
//
//  API client for the PeerTube public instance directory.
//

import Foundation

/// API client for fetching PeerTube instances from the public directory.
actor PeerTubeDirectoryAPI {
    private let httpClient: HTTPClient
    private let baseURL = URL(string: "https://instances.joinpeertube.org")!

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Fetches instances from the public directory.
    /// - Parameters:
    ///   - start: The offset for pagination (default: 0).
    ///   - count: The number of instances to fetch (default: 50).
    /// - Returns: A response containing the total count and array of instances.
    /// - Note: The API does not support server-side filtering by language/country.
    ///         Filtering should be done client-side after fetching all instances.
    func fetchInstances(
        start: Int = 0,
        count: Int = 50
    ) async throws -> PeerTubeDirectoryResponse {
        let query: [String: String] = [
            "start": String(start),
            "count": String(count)
        ]

        let endpoint = GenericEndpoint.get("/api/v1/instances", query: query)
        return try await httpClient.fetch(endpoint, baseURL: baseURL)
    }
}
