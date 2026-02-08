//
//  HTTPClient.swift
//  Yattee
//
//  Modern async/await networking layer using URLSession.
//

import Foundation

/// Actor-based HTTP client for making network requests.
actor HTTPClient {
    // MARK: - Properties

    private let session: URLSession
    private let decoder: JSONDecoder
    private var userAgent: String?
    private var randomizeUserAgentPerRequest: Bool = false

    // MARK: - Initialization

    init(session: URLSession = .shared, decoder: JSONDecoder = .init()) {
        self.session = session
        self.decoder = decoder

        // Configure decoder for common API patterns
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Configuration

    /// Sets the User-Agent header to use for all requests.
    /// - Parameter userAgent: The User-Agent string to use.
    func setUserAgent(_ userAgent: String) {
        self.userAgent = userAgent
    }

    /// Sets whether to generate a new random User-Agent for each request.
    /// - Parameter enabled: If true, ignores the fixed userAgent and generates a new random one per request.
    func setRandomizeUserAgentPerRequest(_ enabled: Bool) {
        self.randomizeUserAgentPerRequest = enabled
    }

    // MARK: - Public Methods

    /// Fetches and decodes a response from the given endpoint.
    /// - Parameters:
    ///   - endpoint: The endpoint to fetch from.
    ///   - baseURL: The base URL to use for the request.
    ///   - customHeaders: Optional custom headers to add to the request (e.g., API keys).
    /// - Returns: The decoded response.
    func fetch<T: Decodable & Sendable>(
        _ endpoint: Endpoint,
        baseURL: URL,
        customHeaders: [String: String]? = nil
    ) async throws -> T {
        let request = try endpoint.urlRequest(baseURL: baseURL)
        return try await perform(request, customHeaders: customHeaders)
    }

    /// Fetches raw data from the given endpoint.
    /// - Parameters:
    ///   - endpoint: The endpoint to fetch from.
    ///   - baseURL: The base URL to use for the request.
    ///   - customHeaders: Optional custom headers to add to the request (e.g., API keys).
    /// - Returns: The raw response data.
    func fetchData(
        _ endpoint: Endpoint,
        baseURL: URL,
        customHeaders: [String: String]? = nil
    ) async throws -> Data {
        let request = try endpoint.urlRequest(baseURL: baseURL)
        return try await performRaw(request, customHeaders: customHeaders)
    }

    /// Sends a request without expecting a response body.
    /// Used for POST/PUT/DELETE operations that return empty responses.
    /// - Parameters:
    ///   - endpoint: The endpoint to send the request to.
    ///   - baseURL: The base URL to use for the request.
    ///   - customHeaders: Optional custom headers to add to the request (e.g., cookies).
    func sendRequest(
        _ endpoint: Endpoint,
        baseURL: URL,
        customHeaders: [String: String]? = nil
    ) async throws {
        let request = try endpoint.urlRequest(baseURL: baseURL)
        _ = try await performRaw(request, customHeaders: customHeaders)
    }

    /// Performs a request and returns the raw data without decoding.
    /// - Parameters:
    ///   - request: The URLRequest to perform.
    ///   - customHeaders: Optional custom headers to add to the request (e.g., API keys).
    /// - Returns: The raw response data.
    func performRaw(_ request: URLRequest, customHeaders: [String: String]? = nil) async throws -> Data {
        var mutableRequest = request

        // Apply User-Agent header
        if randomizeUserAgentPerRequest {
            // Generate a fresh random User-Agent for this request
            mutableRequest.setValue(UserAgentGenerator.generateRandom(), forHTTPHeaderField: "User-Agent")
        } else if let userAgent {
            mutableRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        // Apply custom headers (e.g., X-API-Key for authenticated requests)
        if let customHeaders {
            for (key, value) in customHeaders {
                mutableRequest.setValue(value, forHTTPHeaderField: key)
            }
        }

        let method = mutableRequest.httpMethod ?? "GET"
        let requestURL = mutableRequest.url ?? URL(string: "unknown")!
        let finalRequest = mutableRequest

        await MainActor.run {
            LoggingService.shared.logAPIRequest(method, url: requestURL)
        }

        // Check if task was already cancelled before making the request
        if Task.isCancelled {
            await MainActor.run {
                LoggingService.shared.debug("Request cancelled before execution: \(requestURL)", category: .api)
            }
            throw APIError.cancelled
        }

        let startTime = Date()
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: finalRequest)
        } catch let error as URLError {
            let apiError = mapURLError(error)
            // Add more context for cancelled requests
            if error.code == .cancelled {
                await MainActor.run {
                    LoggingService.shared.debug(
                        "URLSession request cancelled - Task.isCancelled: \(Task.isCancelled)",
                        category: .api
                    )
                }
            }
            await MainActor.run {
                LoggingService.shared.logAPIError(requestURL, error: apiError)
            }
            throw apiError
        } catch {
            await MainActor.run {
                LoggingService.shared.logAPIError(requestURL, error: error)
            }
            throw APIError.unknown(error.localizedDescription)
        }

        let duration = Date().timeIntervalSince(startTime)

        do {
            try validateResponse(response, data: data)
        } catch {
            await MainActor.run {
                LoggingService.shared.logAPIError(requestURL, error: error)
            }
            throw error
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        await MainActor.run {
            LoggingService.shared.logAPIResponse(requestURL, statusCode: statusCode, duration: duration)
        }

        return data
    }

    // MARK: - Private Methods

    private func perform<T: Decodable & Sendable>(
        _ request: URLRequest,
        customHeaders: [String: String]? = nil
    ) async throws -> T {
        let data = try await performRaw(request, customHeaders: customHeaders)

        do {
            return try decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            let errorDescription = describeDecodingError(error)
            Task { @MainActor in
                LoggingService.shared.error("API decoding error: \(errorDescription)", category: .api)
            }
            throw APIError.decodingError(errorDescription)
        }
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        let statusCode = httpResponse.statusCode

        switch statusCode {
        case 200...299:
            return
        case 401:
            throw APIError.unauthorized
        case 404:
            let detail = parseErrorDetail(from: data)
            throw APIError.notFound(detail)
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            throw APIError.rateLimited(retryAfter: retryAfter)
        default:
            let detail = parseErrorDetail(from: data)
            throw APIError.httpError(statusCode: statusCode, message: detail)
        }
    }

    private func mapURLError(_ error: URLError) -> APIError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .notConnectedToInternet, .networkConnectionLost:
            return .noConnection
        case .cancelled:
            return .cancelled
        default:
            return .unknown(error.localizedDescription)
        }
    }

    private func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(let type, let context):
            return "Type mismatch for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(let type, let context):
            return "Null value for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let context):
            return "Data corrupted at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        @unknown default:
            return error.localizedDescription
        }
    }

    /// Parses error detail from JSON response body.
    /// Supports common API error formats: {"detail": "..."}, {"error": "..."}, {"message": "..."}
    private func parseErrorDetail(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Try common error message fields
        if let detail = json["detail"] as? String {
            return detail
        }
        if let error = json["error"] as? String {
            return error
        }
        if let message = json["message"] as? String {
            return message
        }

        return nil
    }
}

