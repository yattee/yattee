//
//  DataExportStructures.swift
//  Yattee
//
//  Codable structures for exporting data to iCloud sync.
//

import Foundation

// MARK: - Subscription Export

/// Codable struct for exporting Subscription to iCloud.
struct SubscriptionExport: Codable {
    let channelID: String
    let sourceRawValue: String
    let instanceURLString: String?
    let name: String
    let channelDescription: String?
    let subscriberCount: Int?
    let avatarURLString: String?
    let bannerURLString: String?
    let isVerified: Bool
    let subscribedAt: Date
    let lastUpdatedAt: Date

    init(from subscription: Subscription) {
        self.channelID = subscription.channelID
        self.sourceRawValue = subscription.sourceRawValue
        self.instanceURLString = subscription.instanceURLString
        self.name = subscription.name
        self.channelDescription = subscription.channelDescription
        self.subscriberCount = subscription.subscriberCount
        self.avatarURLString = subscription.avatarURLString
        self.bannerURLString = subscription.bannerURLString
        self.isVerified = subscription.isVerified
        self.subscribedAt = subscription.subscribedAt
        self.lastUpdatedAt = subscription.lastUpdatedAt
    }
}

// MARK: - Media Source Export

/// Codable struct for exporting MediaSource (WebDAV and SMB) to iCloud.
/// Note: Local folder sources are never synced as they are device-specific.
struct MediaSourceExport: Codable {
    let id: UUID
    let name: String
    let type: String  // "webdav" or "smb"
    let urlString: String
    let username: String?
    let isEnabled: Bool
    let dateAdded: Date
    let allowInvalidCertificates: Bool

    // SMB-specific fields
    let smbWorkgroup: String?
    let smbProtocolVersion: Int32?

    init(from source: MediaSource) {
        self.id = source.id
        self.name = source.name
        self.type = source.type.rawValue
        self.urlString = source.url.absoluteString
        self.username = source.username
        self.isEnabled = source.isEnabled
        self.dateAdded = source.dateAdded
        self.allowInvalidCertificates = source.allowInvalidCertificates
        self.smbWorkgroup = source.smbWorkgroup
        self.smbProtocolVersion = source.smbProtocolVersion?.rawValue
    }

    /// Converts back to a MediaSource. Creates WebDAV or SMB based on type.
    func toMediaSource() -> MediaSource? {
        guard let url = URL(string: urlString) else { return nil }

        // Determine the source type (default to webdav for backward compatibility)
        let sourceType = MediaSourceType(rawValue: type) ?? .webdav

        // Only allow network source types (webdav and smb)
        guard sourceType == .webdav || sourceType == .smb else { return nil }

        return MediaSource(
            id: id,
            name: name,
            type: sourceType,
            url: url,
            isEnabled: isEnabled,
            dateAdded: dateAdded,
            username: username,
            allowInvalidCertificates: allowInvalidCertificates,
            smbWorkgroup: smbWorkgroup,
            smbProtocolVersion: smbProtocolVersion.flatMap { SMBProtocol(rawValue: $0) }
        )
    }
}
