//
//  URLShortenerResolver.swift
//  Yattee
//
//  Best-effort resolver for known URL shortener services (bit.ly, tinyurl, t.co, …).
//  Used to rescue taps on short links in video descriptions and comments: if the
//  redirect target is a URL that `URLRouter` can handle, we open it in-app instead
//  of bouncing out to Safari.
//
//  Off-by-default feature — wired via `SettingsManager.resolveShortLinksEnabled`.
//

import Foundation

enum URLShortenerResolver {
    /// Hosts whose URLs we try to resolve. Kept deliberately narrow so we don't
    /// fire spurious network requests against arbitrary hosts the user taps.
    /// `youtu.be` is intentionally excluded — `URLRouter` already handles it
    /// directly without a network round-trip.
    static let knownHosts: Set<String> = [
        "bit.ly",
        "tinyurl.com",
        "t.co",
        "goo.gl",
        "ow.ly",
        "buff.ly",
        "is.gd",
        "rebrand.ly",
        "shorturl.at",
        "cutt.ly",
        "lnkd.in",
        "tiny.cc",
        "rb.gy"
    ]

    /// Returns true if `url` is hosted on a known shortener service.
    static func isShortener(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let normalizedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return knownHosts.contains(normalizedHost)
    }

    /// Resolves a shortener URL by following redirects. Returns `nil` on any
    /// error (network failure, timeout, non-HTTP response).
    ///
    /// Internally uses `HEAD` first; if the shortener responds 405 Method Not
    /// Allowed (some do), falls back to a single `GET`. Results are cached for
    /// the app lifetime to make repeat taps instant.
    static func resolve(_ url: URL) async -> URL? {
        if let cached = await cache.get(url) {
            return cached
        }

        let resolved = await performResolve(url)
        if let resolved {
            await cache.set(url, resolved: resolved)
        }
        return resolved
    }

    // MARK: - Implementation

    private static func performResolve(_ url: URL) async -> URL? {
        // Try HEAD first — cheapest. Fall back to GET if anything throws or
        // if HEAD doesn't yield a different URL (some servers reject HEAD with
        // a connection reset before following redirects).
        if let viaHead = try? await request(url, method: "HEAD"), viaHead != url {
            return viaHead
        }
        return try? await request(url, method: "GET")
    }

    private static func request(_ url: URL, method: String) async throws -> URL? {
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = method
        // A plain browser-ish UA avoids bot-blocking on a couple of services.
        request.setValue(
            "Mozilla/5.0 (compatible; Yattee URL resolver)",
            forHTTPHeaderField: "User-Agent"
        )

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        config.httpCookieStorage = nil
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        let (_, response) = try await session.data(for: request)
        // URLSession follows redirects by default, so `response.url` is the final URL.
        // We accept any status code here — even a 4xx/5xx final response is fine
        // because we only care about *where* the redirect chain landed, not whether
        // that destination is currently serving content.
        guard let finalURL = response.url, finalURL != url else { return nil }
        return finalURL
    }

    // Bounded in-memory cache. 128 entries is plenty — tapping the same link
    // repeatedly in a session is common; cross-session persistence isn't needed.
    private static let cache = ResolveCache(limit: 128)

    private actor ResolveCache {
        private var storage: [URL: URL] = [:]
        private var order: [URL] = []
        private let limit: Int

        init(limit: Int) { self.limit = limit }

        func get(_ url: URL) -> URL? { storage[url] }

        func set(_ url: URL, resolved: URL) {
            if storage[url] == nil {
                order.append(url)
                if order.count > limit, let oldest = order.first {
                    order.removeFirst()
                    storage[oldest] = nil
                }
            }
            storage[url] = resolved
        }
    }
}
