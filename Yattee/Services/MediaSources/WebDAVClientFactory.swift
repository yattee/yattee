//
//  WebDAVClientFactory.swift
//  Yattee
//
//  Factory for creating WebDAVClient instances with appropriate SSL settings.
//

import Foundation

/// Factory for creating WebDAVClient instances based on media source SSL settings.
final class WebDAVClientFactory: Sendable {
    private let sessionFactory: URLSessionFactory

    init(sessionFactory: URLSessionFactory = .shared) {
        self.sessionFactory = sessionFactory
    }

    /// Creates a WebDAVClient configured for the given media source's SSL requirements.
    /// - Parameter source: The media source to create a client for.
    /// - Returns: A WebDAVClient with appropriate SSL settings.
    func createClient(for source: MediaSource) -> WebDAVClient {
        let session = sessionFactory.session(allowInvalidCertificates: source.allowInvalidCertificates)
        return WebDAVClient(session: session)
    }

    /// Creates a WebDAVClient with explicit SSL settings.
    /// - Parameter allowInvalidCertificates: Whether to bypass SSL certificate validation.
    /// - Returns: A WebDAVClient with the specified SSL settings.
    func createClient(allowInvalidCertificates: Bool) -> WebDAVClient {
        let session = sessionFactory.session(allowInvalidCertificates: allowInvalidCertificates)
        return WebDAVClient(session: session)
    }
}
