//
//  Subscription.swift
//  Yattee
//
//  SwiftData model for channel subscriptions.
//

import Foundation
import SwiftData

/// Represents a subscribed channel.
@Model
final class Subscription {
    // MARK: - Channel Identity

    /// The channel ID string.
    var channelID: String = ""

    /// The content source raw value.
    var sourceRawValue: String = "youtube"

    /// For PeerTube: the instance URL string.
    var instanceURLString: String?

    // MARK: - Channel Metadata

    /// The channel name.
    var name: String = ""

    /// Channel description.
    var channelDescription: String?

    /// Subscriber count (if known).
    var subscriberCount: Int?

    /// Avatar/thumbnail URL string.
    var avatarURLString: String?

    /// Banner URL string.
    var bannerURLString: String?

    /// Whether the channel is verified.
    var isVerified: Bool = false

    // MARK: - Subscription Metadata

    /// When the subscription was created.
    var subscribedAt: Date = Date()

    /// When channel info was last updated.
    var lastUpdatedAt: Date = Date()

    /// When the channel's most recent video was published (for sorting).
    var lastVideoPublishedAt: Date?

    // MARK: - Server Sync (Yattee Server)

    /// The server's subscription ID (for deletion via server API).
    var serverSubscriptionID: Int?

    /// The provider name (e.g., "youtube", "peertube") for server sync.
    /// Used as the `site` field in server API calls.
    var providerName: String?

    /// The channel URL for external/extracted sources (required for feed fetching).
    var channelURLString: String?

    // MARK: - Initialization

    init(
        channelID: String,
        sourceRawValue: String,
        instanceURLString: String? = nil,
        name: String,
        channelDescription: String? = nil,
        subscriberCount: Int? = nil,
        avatarURLString: String? = nil,
        bannerURLString: String? = nil,
        isVerified: Bool = false,
        channelURLString: String? = nil
    ) {
        self.channelID = channelID
        self.sourceRawValue = sourceRawValue
        self.instanceURLString = instanceURLString
        self.name = name
        self.channelDescription = channelDescription
        self.subscriberCount = subscriberCount
        self.avatarURLString = avatarURLString
        self.bannerURLString = bannerURLString
        self.isVerified = isVerified
        self.channelURLString = channelURLString
        self.subscribedAt = Date()
        self.lastUpdatedAt = Date()
    }

    // MARK: - Computed Properties

    /// The content source for this subscription.
    var contentSource: ContentSource {
        let provider = providerName ?? ContentSource.youtubeProvider

        if sourceRawValue == "global" {
            return .global(provider: provider)
        } else if sourceRawValue == "federated",
                  let urlString = instanceURLString,
                  let url = URL(string: urlString) {
            return .federated(provider: providerName ?? ContentSource.peertubeProvider, instance: url)
        }
        return .global(provider: provider)
    }

    /// The site value for server API calls (same as provider).
    var site: String {
        providerName ?? contentSource.provider
    }

    /// The avatar URL if available.
    var avatarURL: URL? {
        avatarURLString.flatMap { URL(string: $0) }
    }

    /// The banner URL if available.
    var bannerURL: URL? {
        bannerURLString.flatMap { URL(string: $0) }
    }

    /// Formatted subscriber count.
    var formattedSubscriberCount: String? {
        guard let count = subscriberCount else { return nil }
        return CountFormatter.compact(count)
    }

    // MARK: - Methods

    /// Updates the channel metadata from fresh data.
    /// Uses a merge strategy: only updates optional fields if the new value is non-nil,
    /// preventing nil values from overwriting valid cached data.
    func update(from channel: Channel) {
        name = channel.name
        isVerified = channel.isVerified
        lastUpdatedAt = Date()

        // Only update optional fields if new value is non-nil
        if let desc = channel.description {
            channelDescription = desc
        }
        if let count = channel.subscriberCount {
            subscriberCount = count
        }
        if let thumb = channel.thumbnailURL {
            avatarURLString = thumb.absoluteString
        }
        if let banner = channel.bannerURL {
            bannerURLString = banner.absoluteString
        }
    }
}

// MARK: - Factory Methods

extension Subscription {
    /// Creates a Subscription from a Channel model.
    static func from(channel: Channel) -> Subscription {
        let sourceRaw: String
        var instanceURL: String?
        var channelURL: String?
        let provider = channel.id.source.provider

        switch channel.id.source {
        case .global(let prov):
            sourceRaw = "global"
            // Construct YouTube channel URL
            if prov == ContentSource.youtubeProvider {
                if channel.id.channelID.hasPrefix("@") {
                    channelURL = "https://www.youtube.com/\(channel.id.channelID)"
                } else {
                    channelURL = "https://www.youtube.com/channel/\(channel.id.channelID)"
                }
            }
        case .federated(_, let instance):
            sourceRaw = "federated"
            instanceURL = instance.absoluteString
            // Construct PeerTube channel URL
            channelURL = instance.appendingPathComponent("video-channels/\(channel.id.channelID)").absoluteString
        case .extracted(_, let originalURL):
            sourceRaw = "extracted"
            channelURL = originalURL.absoluteString
        }

        let subscription = Subscription(
            channelID: channel.id.channelID,
            sourceRawValue: sourceRaw,
            instanceURLString: instanceURL,
            name: channel.name,
            channelDescription: channel.description,
            subscriberCount: channel.subscriberCount,
            avatarURLString: channel.thumbnailURL?.absoluteString,
            bannerURLString: channel.bannerURL?.absoluteString,
            isVerified: channel.isVerified,
            channelURLString: channelURL
        )
        subscription.providerName = provider
        return subscription
    }
}
