//
//  ChannelNotificationSettings.swift
//  Yattee
//
//  SwiftData model for per-channel notification preferences.
//  These settings are synced via iCloud independently of the subscription source.
//

import Foundation
import SwiftData

/// Stores notification preferences for a channel.
/// This is separate from subscriptions so notification settings persist
/// across subscription account changes (local vs Invidious).
@Model
final class ChannelNotificationSettings {
    // MARK: - Properties

    /// The channel ID this setting applies to.
    @Attribute(.unique) var channelID: String = ""

    /// Whether notifications are enabled for this channel.
    var notificationsEnabled: Bool = false

    /// When this setting was last updated.
    var updatedAt: Date = Date()

    /// Source type: "global", "federated", or "extracted".
    var sourceRawValue: String = "global"

    /// Instance URL for federated sources.
    var instanceURLString: String?

    /// Provider name for global sources (e.g. "youtube").
    var globalProvider: String?

    // MARK: - Initialization

    init(
        channelID: String,
        notificationsEnabled: Bool = false,
        sourceRawValue: String = "global",
        instanceURLString: String? = nil,
        globalProvider: String? = nil
    ) {
        self.channelID = channelID
        self.notificationsEnabled = notificationsEnabled
        self.updatedAt = Date()
        self.sourceRawValue = sourceRawValue
        self.instanceURLString = instanceURLString
        self.globalProvider = globalProvider
    }

    // MARK: - Methods

    /// Updates the notifications enabled state and timestamp.
    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        updatedAt = Date()
    }
}
