//
//  DataManager+ChannelNotificationSettings.swift
//  Yattee
//
//  Channel notification settings operations for DataManager.
//

import Foundation
import SwiftData

extension DataManager {
    // MARK: - Channel Notification Settings

    /// Sets notification preferences for a channel.
    /// Creates the settings record if it doesn't exist.
    /// - Parameters:
    ///   - enabled: Whether notifications should be enabled.
    ///   - channelID: The channel ID to set preferences for.
    func setNotificationsEnabled(_ enabled: Bool, for channelID: String) {
        let descriptor = FetchDescriptor<ChannelNotificationSettings>(
            predicate: #Predicate { $0.channelID == channelID }
        )

        do {
            let existing = try modelContext.fetch(descriptor)

            let settings: ChannelNotificationSettings
            if let existingSettings = existing.first {
                // Update existing record
                existingSettings.setNotificationsEnabled(enabled)
                settings = existingSettings
            } else {
                // Derive source info from the matching subscription
                let sub = subscription(for: channelID)
                settings = ChannelNotificationSettings(
                    channelID: channelID,
                    notificationsEnabled: enabled,
                    sourceRawValue: sub?.sourceRawValue ?? "global",
                    instanceURLString: sub?.instanceURLString,
                    globalProvider: sub?.providerName
                )
                modelContext.insert(settings)
            }
            save()

            // Queue for CloudKit sync
            cloudKitSync?.queueChannelNotificationSettingsSave(settings)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to set notification settings", error: error)
        }
    }

    /// Gets notification preferences for a channel.
    /// - Parameter channelID: The channel ID to get preferences for.
    /// - Returns: Whether notifications are enabled. Defaults to false if no settings exist.
    func notificationsEnabled(for channelID: String) -> Bool {
        let descriptor = FetchDescriptor<ChannelNotificationSettings>(
            predicate: #Predicate { $0.channelID == channelID }
        )

        do {
            let results = try modelContext.fetch(descriptor)
            return results.first?.notificationsEnabled ?? false
        } catch {
            LoggingService.shared.logCloudKitError("Failed to fetch notification settings", error: error)
            return false
        }
    }

    /// Gets the notification settings record for a channel.
    /// - Parameter channelID: The channel ID to get settings for.
    /// - Returns: The settings record, or nil if none exists.
    func channelNotificationSettings(for channelID: String) -> ChannelNotificationSettings? {
        let descriptor = FetchDescriptor<ChannelNotificationSettings>(
            predicate: #Predicate { $0.channelID == channelID }
        )

        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            LoggingService.shared.logCloudKitError("Failed to fetch notification settings", error: error)
            return nil
        }
    }

    /// Gets all channel IDs with notifications enabled.
    /// Used for background refresh to determine which channels to check.
    /// - Returns: Array of channel IDs with notifications enabled.
    func channelIDsWithNotificationsEnabled() -> [String] {
        let descriptor = FetchDescriptor<ChannelNotificationSettings>(
            predicate: #Predicate { $0.notificationsEnabled == true }
        )

        do {
            let results = try modelContext.fetch(descriptor)
            return results.map { $0.channelID }
        } catch {
            LoggingService.shared.logCloudKitError("Failed to fetch channels with notifications enabled", error: error)
            return []
        }
    }

    /// Gets all channel notification settings.
    /// - Returns: Array of all notification settings records.
    func allChannelNotificationSettings() -> [ChannelNotificationSettings] {
        let descriptor = FetchDescriptor<ChannelNotificationSettings>(
            sortBy: [SortDescriptor(\.channelID)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to fetch all notification settings", error: error)
            return []
        }
    }

    /// Deletes notification settings for a channel.
    /// - Parameter channelID: The channel ID to delete settings for.
    func deleteNotificationSettings(for channelID: String) {
        let descriptor = FetchDescriptor<ChannelNotificationSettings>(
            predicate: #Predicate { $0.channelID == channelID }
        )

        do {
            let results = try modelContext.fetch(descriptor)
            guard !results.isEmpty else { return }

            // Capture scopes before deleting
            let scopes = results.map {
                SourceScope.from(
                    sourceRawValue: $0.sourceRawValue,
                    globalProvider: $0.globalProvider,
                    instanceURLString: $0.instanceURLString,
                    externalExtractor: nil
                )
            }

            for settings in results {
                modelContext.delete(settings)
            }
            save()

            // Queue scoped CloudKit deletions
            for scope in scopes {
                cloudKitSync?.queueChannelNotificationSettingsDelete(channelID: channelID, scope: scope)
            }
        } catch {
            LoggingService.shared.logCloudKitError("Failed to delete notification settings", error: error)
        }
    }

    /// Inserts or updates notification settings from CloudKit sync.
    /// - Parameter settings: The notification settings to upsert.
    func upsertChannelNotificationSettings(_ settings: ChannelNotificationSettings) {
        let channelID = settings.channelID
        let descriptor = FetchDescriptor<ChannelNotificationSettings>(
            predicate: #Predicate { $0.channelID == channelID }
        )

        do {
            let existing = try modelContext.fetch(descriptor)

            if let existingSettings = existing.first {
                // Update if incoming is newer
                if settings.updatedAt > existingSettings.updatedAt {
                    existingSettings.notificationsEnabled = settings.notificationsEnabled
                    existingSettings.updatedAt = settings.updatedAt
                    existingSettings.sourceRawValue = settings.sourceRawValue
                    existingSettings.instanceURLString = settings.instanceURLString
                    existingSettings.globalProvider = settings.globalProvider
                }
            } else {
                // Insert new record
                modelContext.insert(settings)
            }
            save()
        } catch {
            LoggingService.shared.logCloudKitError("Failed to upsert notification settings", error: error)
        }
    }
}
