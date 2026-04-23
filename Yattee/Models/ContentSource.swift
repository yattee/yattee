//
//  ContentSource.swift
//  Yattee
//
//  Defines the source of video content by identity paradigm.
//

import Foundation

/// Represents the source of video content by its identity paradigm.
///
/// Global content has universally unique IDs that work across any mirror instance.
/// Federated content belongs to a specific instance - the ID is only unique within that instance.
/// Extracted content comes from external sites via yt-dlp and requires the original URL for re-extraction.
enum ContentSource: Codable, Hashable, Sendable {
    /// Content with globally unique IDs (e.g., YouTube, Dailymotion).
    /// Works across any mirror instance.
    case global(provider: String)

    /// Content specific to a federated instance (e.g., PeerTube, Funkwhale).
    /// The instance URL is part of the video's identity.
    case federated(provider: String, instance: URL)

    /// Content requiring URL-based extraction (Vimeo, Twitter, TikTok, etc.).
    /// Original URL preserved for stream re-extraction via yt-dlp.
    case extracted(extractor: String, originalURL: URL)

    // MARK: - Provider Constants

    static let youtubeProvider = "youtube"
    static let peertubeProvider = "peertube"

    // MARK: - Display

    var displayName: String {
        switch self {
        case .global(let provider):
            if provider == Self.youtubeProvider {
                return String(localized: "source.youtube")
            }
            return provider.prefix(1).uppercased() + provider.dropFirst()
        case .federated(_, let instance):
            return instance.host ?? String(localized: "instances.type.peertube")
        case .extracted(let extractor, let originalURL):
            // Capitalize the extractor name, or fall back to URL host
            let formatted = extractor.replacingOccurrences(of: "_", with: " ")
            if formatted.isEmpty {
                return originalURL.host ?? "External"
            }
            return formatted.prefix(1).uppercased() + formatted.dropFirst()
        }
    }

    var shortName: String {
        switch self {
        case .global(let provider):
            if provider == Self.youtubeProvider {
                return "YT"
            }
            return String(provider.prefix(4)).uppercased()
        case .federated(_, let instance):
            return instance.host?.components(separatedBy: ".").first?.prefix(8).description ?? "PT"
        case .extracted(let extractor, _):
            // Use first 4 chars of extractor name, uppercased
            return String(extractor.prefix(4)).uppercased()
        }
    }

    var provider: String {
        switch self {
        case .global(let provider):
            return provider
        case .federated(let provider, _):
            return provider
        case .extracted(let extractor, _):
            return extractor
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case provider
        case instance
        case extractor
        case originalURL
    }

    private enum SourceType: String, Codable {
        case global
        case federated
        case extracted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SourceType.self, forKey: .type)

        switch type {
        case .global:
            let provider = try container.decode(String.self, forKey: .provider)
            self = .global(provider: provider)
        case .federated:
            let provider = try container.decode(String.self, forKey: .provider)
            let instance = try container.decode(URL.self, forKey: .instance)
            self = .federated(provider: provider, instance: instance)
        case .extracted:
            let extractor = try container.decode(String.self, forKey: .extractor)
            let originalURL = try container.decode(URL.self, forKey: .originalURL)
            self = .extracted(extractor: extractor, originalURL: originalURL)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .global(let provider):
            try container.encode(SourceType.global, forKey: .type)
            try container.encode(provider, forKey: .provider)
        case .federated(let provider, let instance):
            try container.encode(SourceType.federated, forKey: .type)
            try container.encode(provider, forKey: .provider)
            try container.encode(instance, forKey: .instance)
        case .extracted(let extractor, let originalURL):
            try container.encode(SourceType.extracted, forKey: .type)
            try container.encode(extractor, forKey: .extractor)
            try container.encode(originalURL, forKey: .originalURL)
        }
    }
}

// MARK: - Identifiable Conformance

extension ContentSource: Identifiable {
    var id: String {
        switch self {
        case .global(let provider):
            return "global:\(provider)"
        case .federated(let provider, let instance):
            return "federated:\(provider):\(instance.absoluteString)"
        case .extracted(let extractor, let originalURL):
            return "extracted:\(extractor):\(originalURL.absoluteString.hashValue)"
        }
    }
}

// MARK: - Comparable

extension ContentSource: Comparable {
    static func < (lhs: ContentSource, rhs: ContentSource) -> Bool {
        switch (lhs, rhs) {
        // Global comes first
        case (.global, .federated), (.global, .extracted):
            return true
        case (.federated, .global), (.extracted, .global):
            return false
        // Federated comes before extracted
        case (.federated, .extracted):
            return true
        case (.extracted, .federated):
            return false
        // Compare within same type
        case (.global(let lProvider), .global(let rProvider)):
            return lProvider < rProvider
        case (.federated(let lProvider, let lInstance), .federated(let rProvider, let rInstance)):
            if lProvider != rProvider {
                return lProvider < rProvider
            }
            return lInstance.absoluteString < rInstance.absoluteString
        case (.extracted(let lExt, let lURL), .extracted(let rExt, let rURL)):
            if lExt != rExt {
                return lExt < rExt
            }
            return lURL.absoluteString < rURL.absoluteString
        }
    }
}
