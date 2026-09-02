//
//  HTTPClientFactory.swift
//  Yattee
//
//  Factory for creating HTTPClient instances with appropriate SSL settings.
//

import Foundation

/// The User-Agent every client a factory mints should identify itself with.
///
/// Held apart from the factories so there is one answer for the whole process.
/// A per-instance client is built deep inside `ContentService`, from a factory
/// nobody outside it can reach, and the app's User-Agent has to reach it too:
/// some instances only answer requests whose User-Agent starts with
/// `Yattee/<version>`, and a client that sends none gets a 401 the shared
/// client never sees.
final class UserAgentConfiguration: @unchecked Sendable {
    static let shared = UserAgentConfiguration()

    private let lock = NSLock()
    private var userAgent: String?
    private var randomizePerRequest = false

    /// Records the User-Agent settings to apply from now on. Clients already
    /// built keep what they were given — they have their own setters.
    func update(userAgent: String?, randomizePerRequest: Bool) {
        lock.lock()
        defer { lock.unlock() }
        self.userAgent = userAgent
        self.randomizePerRequest = randomizePerRequest
    }

    /// The settings as they stand.
    func current() -> (userAgent: String?, randomizePerRequest: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (userAgent, randomizePerRequest)
    }
}

/// Factory for creating HTTPClient instances based on instance SSL settings.
final class HTTPClientFactory: Sendable {
    private let sessionFactory: URLSessionFactory
    private let userAgentConfiguration: UserAgentConfiguration

    init(
        sessionFactory: URLSessionFactory = .shared,
        userAgentConfiguration: UserAgentConfiguration = .shared
    ) {
        self.sessionFactory = sessionFactory
        self.userAgentConfiguration = userAgentConfiguration
    }

    /// Creates an HTTPClient configured for the given instance's SSL requirements.
    /// - Parameter instance: The instance to create a client for.
    /// - Returns: An HTTPClient with appropriate SSL settings.
    func createClient(for instance: Instance) -> HTTPClient {
        makeClient(session: sessionFactory.session(allowInvalidCertificates: instance.allowInvalidCertificates))
    }

    /// Creates an HTTPClient with explicit SSL settings.
    /// - Parameter allowInvalidCertificates: Whether to bypass SSL certificate validation.
    /// - Returns: An HTTPClient with the specified SSL settings.
    func createClient(allowInvalidCertificates: Bool) -> HTTPClient {
        makeClient(session: sessionFactory.session(allowInvalidCertificates: allowInvalidCertificates))
    }

    /// Creates an HTTPClient with low network priority for background/prefetch work.
    /// - Returns: An HTTPClient configured with `.background` network service type.
    func createLowPriorityClient() -> HTTPClient {
        makeClient(session: sessionFactory.lowPrioritySession())
    }

    /// Builds the client with the current User-Agent baked in.
    ///
    /// Passed through the initializer rather than set afterwards: these clients
    /// are handed straight to an API that sends its first request immediately,
    /// and a `Task` to configure them would sometimes lose that race.
    private func makeClient(session: URLSession) -> HTTPClient {
        let configuration = userAgentConfiguration.current()
        return HTTPClient(
            session: session,
            userAgent: configuration.userAgent,
            randomizeUserAgentPerRequest: configuration.randomizePerRequest
        )
    }
}
