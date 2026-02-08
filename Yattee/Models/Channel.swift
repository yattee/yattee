//
//  Channel.swift
//  Yattee
//
//  Represents a video channel/author.
//

@preconcurrency import Foundation

/// Represents a channel from any content source.
struct Channel: Identifiable, Codable, Hashable, Sendable {
    /// Unique identifier for this channel.
    let id: ChannelID

    /// The channel name.
    let name: String

    /// Channel description/about text.
    let description: String?

    /// Subscriber count if available.
    let subscriberCount: Int?

    /// Total video count if available.
    let videoCount: Int?

    /// Channel thumbnail/avatar URL.
    let thumbnailURL: URL?

    /// Channel banner image URL.
    let bannerURL: URL?

    /// Whether the channel is verified.
    let isVerified: Bool

    // MARK: - Computed Properties

    var formattedSubscriberCount: String? {
        guard let subscriberCount else { return nil }
        return CountFormatter.compact(subscriberCount)
    }

    // MARK: - Initialization

    init(
        id: ChannelID,
        name: String,
        description: String? = nil,
        subscriberCount: Int? = nil,
        videoCount: Int? = nil,
        thumbnailURL: URL? = nil,
        bannerURL: URL? = nil,
        isVerified: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.subscriberCount = subscriberCount
        self.videoCount = videoCount
        self.thumbnailURL = thumbnailURL
        self.bannerURL = bannerURL
        self.isVerified = isVerified
    }
}

// MARK: - Channel ID

/// Unique identifier for a channel, combining source and channel ID.
struct ChannelID: Codable, Hashable, Sendable {
    /// The content source.
    let source: ContentSource

    /// The channel ID within that source.
    let channelID: String

    init(source: ContentSource, channelID: String) {
        self.source = source
        self.channelID = channelID
    }

    /// Creates a global channel ID (e.g., YouTube).
    static func global(_ channelID: String, provider: String = ContentSource.youtubeProvider) -> ChannelID {
        ChannelID(source: .global(provider: provider), channelID: channelID)
    }

    /// Creates a federated channel ID (e.g., PeerTube).
    static func federated(_ channelID: String, provider: String = ContentSource.peertubeProvider, instance: URL) -> ChannelID {
        ChannelID(source: .federated(provider: provider, instance: instance), channelID: channelID)
    }

    /// Creates an extracted channel ID for sites supported by yt-dlp.
    static func extracted(_ channelID: String, extractor: String, originalURL: URL) -> ChannelID {
        ChannelID(source: .extracted(extractor: extractor, originalURL: originalURL), channelID: channelID)
    }
}

extension ChannelID: Identifiable {
    var id: String {
        switch source {
        case .global(let provider):
            return "global:\(provider):\(channelID)"
        case .federated(let provider, let instance):
            return "federated:\(provider):\(instance.host ?? ""):\(channelID)"
        case .extracted(let extractor, _):
            return "extracted:\(extractor):\(channelID)"
        }
    }
}
