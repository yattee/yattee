//
//  MediaSourceError.swift
//  Yattee
//
//  Errors for media source operations.
//

import Foundation

/// Errors that can occur during media source operations.
enum MediaSourceError: Error, LocalizedError, Equatable, Sendable {
    /// Failed to connect to the media source.
    case connectionFailed(String)

    /// Authentication failed or is required.
    case authenticationFailed

    /// The requested path was not found.
    case pathNotFound(String)

    /// Failed to parse the response (WebDAV XML, etc.).
    case parsingFailed(String)

    /// The path is not a directory.
    case notADirectory

    /// The source returned an invalid response.
    case invalidResponse

    /// The bookmark could not be resolved (local folders).
    case bookmarkResolutionFailed

    /// Access to the file/folder was denied.
    case accessDenied

    /// The operation timed out.
    case timeout

    /// No network connection available.
    case noConnection

    /// An unknown error occurred.
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .authenticationFailed:
            return "Authentication failed"
        case .pathNotFound(let path):
            return "Path not found: \(path)"
        case .parsingFailed(let message):
            return "Failed to parse response: \(message)"
        case .notADirectory:
            return "The path is not a directory"
        case .invalidResponse:
            return "Invalid response from server"
        case .bookmarkResolutionFailed:
            return "Could not access the folder. Please re-add it."
        case .accessDenied:
            return "Access denied"
        case .timeout:
            return "Request timed out"
        case .noConnection:
            return "No network connection"
        case .unknown(let message):
            return message
        }
    }

    /// Whether this error is likely recoverable by retrying.
    var isRetryable: Bool {
        switch self {
        case .timeout, .noConnection, .connectionFailed:
            return true
        default:
            return false
        }
    }

    static func == (lhs: MediaSourceError, rhs: MediaSourceError) -> Bool {
        switch (lhs, rhs) {
        case (.authenticationFailed, .authenticationFailed),
             (.notADirectory, .notADirectory),
             (.invalidResponse, .invalidResponse),
             (.bookmarkResolutionFailed, .bookmarkResolutionFailed),
             (.accessDenied, .accessDenied),
             (.timeout, .timeout),
             (.noConnection, .noConnection):
            return true
        case (.connectionFailed(let lMsg), .connectionFailed(let rMsg)):
            return lMsg == rMsg
        case (.pathNotFound(let lPath), .pathNotFound(let rPath)):
            return lPath == rPath
        case (.parsingFailed(let lMsg), .parsingFailed(let rMsg)):
            return lMsg == rMsg
        case (.unknown(let lMsg), .unknown(let rMsg)):
            return lMsg == rMsg
        default:
            return false
        }
    }
}
