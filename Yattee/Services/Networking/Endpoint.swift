//
//  Endpoint.swift
//  Yattee
//
//  Type-safe endpoint protocol for API requests.
//

import Foundation

/// HTTP methods supported by the API.
enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// Protocol defining an API endpoint.
protocol Endpoint: Sendable {
    /// The path component of the URL (e.g., "/api/v1/videos").
    var path: String { get }

    /// The HTTP method for this endpoint.
    var method: HTTPMethod { get }

    /// Query parameters to append to the URL.
    var queryItems: [URLQueryItem]? { get }

    /// HTTP headers to include in the request.
    var headers: [String: String]? { get }

    /// The body data for POST/PUT/PATCH requests.
    var body: Data? { get }

    /// Timeout interval for this specific request.
    var timeout: TimeInterval { get }
}

// MARK: - Default Implementations

extension Endpoint {
    var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem]? { nil }
    var headers: [String: String]? { nil }
    var body: Data? { nil }
    var timeout: TimeInterval { 30 }

    /// Constructs a URLRequest from this endpoint and a base URL.
    func urlRequest(baseURL: URL) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)
        components?.queryItems = queryItems?.isEmpty == false ? queryItems : nil

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeout

        // Set default headers
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Set custom headers
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Set body for non-GET requests
        if let body, method != .get {
            request.httpBody = body
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        return request
    }
}

// MARK: - Generic Endpoints

/// A generic endpoint that can be configured inline.
struct GenericEndpoint: Endpoint, Sendable {
    let path: String
    let method: HTTPMethod
    let queryItems: [URLQueryItem]?
    let headers: [String: String]?
    let body: Data?
    let timeout: TimeInterval

    init(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String]? = nil,
        body: Data? = nil,
        timeout: TimeInterval = 30
    ) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }

    /// Creates a GET endpoint with query parameters.
    nonisolated static func get(_ path: String, query: [String: String] = [:]) -> GenericEndpoint {
        let queryItems = query.isEmpty ? nil : query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return GenericEndpoint(path: path, queryItems: queryItems)
    }

    /// Creates a GET endpoint with custom headers.
    nonisolated static func get(_ path: String, customHeaders: [String: String]) -> GenericEndpoint {
        return GenericEndpoint(path: path, headers: customHeaders)
    }

    /// Creates a POST endpoint with an encodable body.
    nonisolated static func post<T: Encodable>(_ path: String, body: T, encoder: JSONEncoder = JSONEncoder()) -> GenericEndpoint {
        let bodyData = try? encoder.encode(body)
        return GenericEndpoint(path: path, method: .post, body: bodyData)
    }

    /// Creates a POST endpoint without a body (e.g., for subscription endpoints).
    nonisolated static func post(_ path: String) -> GenericEndpoint {
        return GenericEndpoint(path: path, method: .post)
    }

    /// Creates a DELETE endpoint.
    nonisolated static func delete(_ path: String) -> GenericEndpoint {
        return GenericEndpoint(path: path, method: .delete)
    }
}
