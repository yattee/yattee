//
//  HTTPClientFactory.swift
//  Yattee
//
//  Factory for creating HTTPClient instances with appropriate SSL settings.
//

import Foundation

/// Factory for creating HTTPClient instances based on instance SSL settings.
final class HTTPClientFactory: Sendable {
    private let sessionFactory: URLSessionFactory

    init(sessionFactory: URLSessionFactory = .shared) {
        self.sessionFactory = sessionFactory
    }

    /// Creates an HTTPClient configured for the given instance's SSL requirements.
    /// - Parameter instance: The instance to create a client for.
    /// - Returns: An HTTPClient with appropriate SSL settings.
    func createClient(for instance: Instance) -> HTTPClient {
        let session = sessionFactory.session(allowInvalidCertificates: instance.allowInvalidCertificates)
        return HTTPClient(session: session)
    }

    /// Creates an HTTPClient with explicit SSL settings.
    /// - Parameter allowInvalidCertificates: Whether to bypass SSL certificate validation.
    /// - Returns: An HTTPClient with the specified SSL settings.
    func createClient(allowInvalidCertificates: Bool) -> HTTPClient {
        let session = sessionFactory.session(allowInvalidCertificates: allowInvalidCertificates)
        return HTTPClient(session: session)
    }

    /// Creates an HTTPClient with low network priority for background/prefetch work.
    /// - Returns: An HTTPClient configured with `.background` network service type.
    func createLowPriorityClient() -> HTTPClient {
        let session = sessionFactory.lowPrioritySession()
        return HTTPClient(session: session)
    }
}
