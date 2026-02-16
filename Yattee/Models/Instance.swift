//
//  Instance.swift
//  Yattee
//
//  Represents a backend instance (Invidious, Piped, PeerTube, or Yattee Server).
//

import Foundation

/// The type of backend instance.
enum InstanceType: String, Codable, CaseIterable, Sendable {
    case invidious
    case piped
    case peertube
    case yatteeServer

    var displayName: String {
        switch self {
        case .invidious: return String(localized: "instances.type.invidious")
        case .piped: return String(localized: "instances.type.piped")
        case .peertube: return String(localized: "instances.type.peertube")
        case .yatteeServer: return String(localized: "instances.type.yatteeServer")
        }
    }

    var systemImage: String {
        "globe"
    }

    var contentSource: ContentSource {
        switch self {
        case .invidious, .piped, .yatteeServer:
            return .global(provider: ContentSource.youtubeProvider)
        case .peertube:
            // For PeerTube, this should be called with the specific instance URL
            fatalError("Use contentSource(for:) for PeerTube instances")
        }
    }

    func contentSource(for url: URL) -> ContentSource {
        switch self {
        case .invidious, .piped, .yatteeServer:
            return .global(provider: ContentSource.youtubeProvider)
        case .peertube:
            return .federated(provider: ContentSource.peertubeProvider, instance: url)
        }
    }
}

/// Represents a backend instance configuration.
struct Instance: Identifiable, Codable, Hashable, Sendable {
    /// Unique identifier for this instance configuration.
    let id: UUID

    /// The type of this instance.
    let type: InstanceType

    /// The base URL of the instance.
    let url: URL

    /// Optional user-defined name for this instance.
    var name: String?

    /// Whether this instance is currently enabled.
    var isEnabled: Bool

    /// The date this instance was added.
    let dateAdded: Date

    /// Optional API key if required by the instance.
    var apiKey: String?

    /// Whether to allow invalid/self-signed SSL certificates.
    var allowInvalidCertificates: Bool

    /// Whether to route video streams through this instance instead of connecting directly to YouTube CDN.
    var proxiesVideos: Bool

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        type: InstanceType,
        url: URL,
        name: String? = nil,
        isEnabled: Bool = true,
        dateAdded: Date = Date(),
        apiKey: String? = nil,
        allowInvalidCertificates: Bool = false,
        proxiesVideos: Bool = false
    ) {
        self.id = id
        self.type = type
        self.url = url
        self.name = name
        self.isEnabled = isEnabled
        self.dateAdded = dateAdded
        self.apiKey = apiKey
        self.allowInvalidCertificates = allowInvalidCertificates
        self.proxiesVideos = proxiesVideos
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(InstanceType.self, forKey: .type)
        url = try container.decode(URL.self, forKey: .url)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        allowInvalidCertificates = try container.decode(Bool.self, forKey: .allowInvalidCertificates)
        proxiesVideos = try container.decodeIfPresent(Bool.self, forKey: .proxiesVideos) ?? false
    }

    // MARK: - Computed Properties

    var displayName: String {
        name ?? url.host ?? url.absoluteString
    }

    var contentSource: ContentSource {
        type.contentSource(for: url)
    }

    /// Whether this instance provides YouTube content.
    var isYouTubeInstance: Bool {
        type == .invidious || type == .piped || type == .yatteeServer
    }

    /// Whether this instance is a PeerTube instance.
    var isPeerTubeInstance: Bool {
        type == .peertube
    }

    /// Whether this instance is a Yattee Server instance.
    var isYatteeServerInstance: Bool {
        type == .yatteeServer
    }
}

// MARK: - Instance Capabilities

extension Instance {
    /// Whether this instance supports advanced search filters (sort, date, duration, features).
    var supportsSearchFilters: Bool {
        type == .invidious || type == .yatteeServer
    }

    /// Whether this instance supports user authentication/login.
    var supportsAuthentication: Bool {
        type == .invidious || type == .piped
    }

    /// Whether this instance supports subscription feed.
    var supportsFeed: Bool {
        type == .invidious || type == .piped
    }

    /// Whether this instance supports search suggestions/autocomplete.
    var supportsSuggestions: Bool {
        type == .invidious || type == .piped || type == .yatteeServer
    }

    /// Whether this instance supports the popular videos endpoint.
    var supportsPopular: Bool {
        type == .invidious || type == .yatteeServer
    }

    /// Whether this instance supports proxying video streams through itself.
    var supportsVideoProxying: Bool {
        type == .invidious || type == .piped
    }
}

// MARK: - Instance Validation

extension Instance {
    /// Validates the instance URL format.
    static func validateURL(_ urlString: String) -> URL? {
        guard var components = URLComponents(string: urlString) else {
            return nil
        }

        // Default to HTTPS if no scheme provided, but preserve explicit HTTP
        // (needed for local/private network servers like yt-dlp server)
        if components.scheme == nil {
            components.scheme = "https"
        }

        // Remove trailing slash from path
        if components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }

        return components.url
    }

    /// Checks if a string is an IPv4 or IPv6 address.
    static func isIPAddress(_ string: String) -> Bool {
        // IPv4: four groups of 1-3 digits separated by dots
        let ipv4Pattern = "^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$"
        if string.range(of: ipv4Pattern, options: .regularExpression) != nil {
            return true
        }

        // IPv6: contains colons (simplified check)
        if string.contains(":") && !string.contains("://") {
            return true
        }

        return false
    }

    /// Infers the appropriate scheme for a URL string based on the host.
    /// - IP addresses default to http:// (common for local servers)
    /// - Domain names default to https://
    /// - Explicit schemes are preserved
    static func inferScheme(for urlString: String) -> String {
        // Already has a scheme
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") || urlString.hasPrefix("smb://") {
            if urlString.hasPrefix("http://") { return "http" }
            if urlString.hasPrefix("https://") { return "https" }
            if urlString.hasPrefix("smb://") { return "smb" }
        }

        // Extract host part (before any path or port)
        let hostPart = urlString
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .components(separatedBy: "/").first ?? urlString

        // Remove port if present
        let hostWithoutPort = hostPart.components(separatedBy: ":").first ?? hostPart

        // IP addresses use http (common for local servers)
        if isIPAddress(hostWithoutPort) {
            return "http"
        }

        // Domain names use https
        return "https"
    }

    /// Normalizes a source URL string, applying appropriate scheme and cleaning up the URL.
    /// - Parameter urlString: The raw URL input from user
    /// - Returns: A normalized URL or nil if invalid
    static func normalizeSourceURL(_ urlString: String) -> URL? {
        var input = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle SMB URLs specially
        if input.lowercased().hasPrefix("smb://") {
            return URL(string: input)
        }

        // Add scheme if missing
        if !input.lowercased().hasPrefix("http://") && !input.lowercased().hasPrefix("https://") {
            let scheme = inferScheme(for: input)
            input = "\(scheme)://\(input)"
        }

        guard var components = URLComponents(string: input) else {
            return nil
        }

        // Remove trailing slash from path
        if components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }

        // Strip embedded credentials (security best practice)
        components.user = nil
        components.password = nil

        return components.url
    }
}
