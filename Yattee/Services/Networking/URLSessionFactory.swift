//
//  URLSessionFactory.swift
//  Yattee
//
//  Factory for creating URLSession instances with appropriate SSL settings.
//

import Foundation

/// Factory for creating URLSession instances based on SSL validation requirements.
final class URLSessionFactory: Sendable {
    /// Shared instance for app-wide use.
    static let shared = URLSessionFactory()

    /// The delegate used for bypassing SSL certificate validation.
    private let insecureDelegate = InsecureURLSessionDelegate()

    /// Cached insecure URLSession instance.
    private let insecureSession: URLSession

    /// Cached low-priority URLSession for background/prefetch work.
    private let lowPriorityURLSession: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300

        self.insecureSession = URLSession(
            configuration: config,
            delegate: insecureDelegate,
            delegateQueue: nil
        )

        // Low-priority session for DeArrow and similar background work
        let lowPriorityConfig = URLSessionConfiguration.default
        lowPriorityConfig.timeoutIntervalForRequest = 30
        lowPriorityConfig.timeoutIntervalForResource = 300
        lowPriorityConfig.networkServiceType = .background
        lowPriorityConfig.waitsForConnectivity = true

        self.lowPriorityURLSession = URLSession(configuration: lowPriorityConfig)
    }

    /// Returns an appropriate URLSession based on SSL validation requirements.
    /// - Parameter allowInvalidCertificates: If true, returns a session that bypasses SSL validation.
    /// - Returns: A URLSession configured for the requested SSL mode.
    func session(allowInvalidCertificates: Bool) -> URLSession {
        if allowInvalidCertificates {
            return insecureSession
        } else {
            return URLSession.shared
        }
    }

    /// Returns a low-priority URLSession for background/prefetch work.
    /// Uses `.background` network service type for OS-level bandwidth deprioritization.
    func lowPrioritySession() -> URLSession {
        lowPriorityURLSession
    }
}
