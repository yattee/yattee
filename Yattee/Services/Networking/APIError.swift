//
//  APIError.swift
//  Yattee
//
//  Typed errors for network operations.
//

import Foundation

/// Errors that can occur during API operations.
enum APIError: Error, LocalizedError, Equatable, Sendable {
    /// The URL could not be constructed.
    case invalidURL

    /// The request failed with an HTTP status code.
    case httpError(statusCode: Int, message: String?)

    /// The response could not be decoded.
    case decodingError(String)

    /// The request timed out.
    case timeout

    /// No network connection available.
    case noConnection

    /// The request was cancelled.
    case cancelled

    /// Server returned an error message.
    case serverError(String)

    /// Rate limited by the server.
    case rateLimited(retryAfter: TimeInterval?)

    /// Authentication required or failed.
    case unauthorized

    /// Resource not found, with optional server-provided detail message.
    case notFound(String?)

    /// Comments are disabled for this video.
    case commentsDisabled

    /// No suitable instance available.
    case noInstance

    /// No playable streams available.
    case noStreams

    /// The request parameters were invalid.
    case invalidRequest

    /// Operation not supported by this instance type.
    case notSupported

    /// An unknown error occurred.
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .httpError(let statusCode, let message):
            if let message {
                return message
            }
            return "HTTP error: \(statusCode)"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        case .timeout:
            return "Request timed out"
        case .noConnection:
            return "No network connection"
        case .cancelled:
            return "Request was cancelled"
        case .serverError(let message):
            return "Server error: \(message)"
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Rate limited. Retry after \(Int(retryAfter)) seconds"
            }
            return "Rate limited"
        case .unauthorized:
            return "Authentication required"
        case .notFound(let detail):
            if let detail {
                return detail
            }
            return "Resource not found"
        case .commentsDisabled:
            return "Comments are disabled"
        case .noInstance:
            return "No suitable instance available"
        case .noStreams:
            return "No playable streams available"
        case .invalidRequest:
            return "Invalid request"
        case .notSupported:
            return "Operation not supported"
        case .unknown(let message):
            return message
        }
    }

    /// Whether this error is likely recoverable by retrying.
    var isRetryable: Bool {
        switch self {
        case .timeout, .noConnection, .rateLimited:
            return true
        case .httpError(let statusCode, _):
            return statusCode >= 500 || statusCode == 429
        default:
            return false
        }
    }

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL),
             (.timeout, .timeout),
             (.noConnection, .noConnection),
             (.cancelled, .cancelled),
             (.unauthorized, .unauthorized),
             (.commentsDisabled, .commentsDisabled),
             (.noInstance, .noInstance),
             (.noStreams, .noStreams),
             (.invalidRequest, .invalidRequest),
             (.notSupported, .notSupported):
            return true
        case (.notFound(let lDetail), .notFound(let rDetail)):
            return lDetail == rDetail
        case (.httpError(let lCode, let lMsg), .httpError(let rCode, let rMsg)):
            return lCode == rCode && lMsg == rMsg
        case (.decodingError(let lMsg), .decodingError(let rMsg)):
            return lMsg == rMsg
        case (.serverError(let lMsg), .serverError(let rMsg)):
            return lMsg == rMsg
        case (.rateLimited(let lRetry), .rateLimited(let rRetry)):
            return lRetry == rRetry
        case (.unknown(let lMsg), .unknown(let rMsg)):
            return lMsg == rMsg
        default:
            return false
        }
    }

    /// Creates a decoding error from a Swift DecodingError.
    static func decodingError(_ error: DecodingError) -> APIError {
        switch error {
        case .typeMismatch(let type, let context):
            return .decodingError("Type mismatch for \(type): \(context.debugDescription)")
        case .valueNotFound(let type, let context):
            return .decodingError("Value not found for \(type): \(context.debugDescription)")
        case .keyNotFound(let key, let context):
            return .decodingError("Key '\(key.stringValue)' not found: \(context.debugDescription)")
        case .dataCorrupted(let context):
            return .decodingError("Data corrupted: \(context.debugDescription)")
        @unknown default:
            return .decodingError(error.localizedDescription)
        }
    }
}
