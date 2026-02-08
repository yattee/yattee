//
//  GitHubAPI.swift
//  Yattee
//
//  GitHub API client for fetching repository contributors.
//

import Foundation

/// GitHub API client with caching.
actor GitHubAPI {
    private let httpClient: HTTPClient

    /// Cache for contributors with timestamp.
    private var contributorsCache: (contributors: [GitHubContributor], timestamp: Date)?

    /// Cache duration: 1 hour.
    private static let cacheDuration: TimeInterval = 60 * 60

    /// GitHub API base URL.
    private static let baseURL = URL(string: "https://api.github.com")!

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Fetches contributors for the Yattee repository.
    /// Results are cached for 1 hour.
    func contributors() async throws -> [GitHubContributor] {
        // Check cache first
        if let cached = contributorsCache,
           Date().timeIntervalSince(cached.timestamp) < Self.cacheDuration {
            return cached.contributors
        }

        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("/repos/yattee/yattee/contributors"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "per_page", value: "100")
        ]

        guard let url = components.url else {
            throw APIError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let data = try await httpClient.performRaw(request)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let contributors = try decoder.decode([GitHubContributor].self, from: data)

            // Cache the result
            contributorsCache = (contributors, Date())

            Task { @MainActor in
                LoggingService.shared.debug("GitHub: fetched \(contributors.count) contributors", category: .api)
            }

            return contributors
        } catch let error as APIError {
            if case .rateLimited = error {
                Task { @MainActor in
                    LoggingService.shared.warning("GitHub API rate limited", category: .api)
                }
            }
            throw error
        } catch let error as DecodingError {
            Task { @MainActor in
                LoggingService.shared.error("GitHub decode error: \(error)", category: .api)
            }
            throw APIError.decodingError(error)
        }
    }

    /// Clears the cache.
    func clearCache() {
        contributorsCache = nil
    }
}
