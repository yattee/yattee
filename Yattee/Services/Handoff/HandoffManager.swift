//
//  HandoffManager.swift
//  Yattee
//
//  Manages Apple Handoff activities for seamless cross-device continuation.
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Manages Apple Handoff activities for seamless cross-device continuation.
@MainActor
@Observable
final class HandoffManager {
    // MARK: - Activity Type

    static let activityType = AppIdentifiers.handoffActivityType

    // MARK: - UserInfo Keys

    private enum UserInfoKey {
        static let destinationType = "destinationType"
        static let videoID = "videoID"
        static let videoUUID = "videoUUID"
        static let videoSource = "videoSource"
        static let channelID = "channelID"
        static let channelSource = "channelSource"
        static let playlistID = "playlistID"
        static let playlistSource = "playlistSource"
        static let localPlaylistUUID = "localPlaylistUUID"
        static let searchQuery = "searchQuery"
        static let playbackTime = "playbackTime"
        static let externalURL = "externalURL"
        static let instanceURL = "instanceURL"
        static let instanceType = "instanceType"
    }

    // MARK: - Destination Types

    private enum DestinationType: String {
        case video
        case channel
        case playlist
        case localPlaylist
        case search
        case subscriptions
        case continueWatching
        case downloads
        case history
        case bookmarks
        case playlists
        case channels  // Subscribed channels list
        case externalVideo
        case externalChannel
        case instanceBrowse
    }

    // MARK: - Properties

    private var currentActivity: NSUserActivity?
    private weak var playerState: PlayerState?
    private weak var settingsManager: SettingsManager?

    // MARK: - Initialization

    init() {}

    func setPlayerState(_ state: PlayerState) {
        self.playerState = state
    }

    func setSettingsManager(_ settings: SettingsManager) {
        self.settingsManager = settings
    }

    // MARK: - Activity Creation

    /// Updates the current activity for a navigation destination.
    func updateActivity(for destination: NavigationDestination) {
        // Check if Handoff is enabled in settings
        guard settingsManager?.handoffEnabled != false else {
            invalidateCurrentActivity()
            return
        }

        // Disable Handoff when incognito mode is active to preserve privacy
        guard settingsManager?.incognitoModeEnabled != true else {
            invalidateCurrentActivity()
            return
        }

        invalidateCurrentActivity()

        let activity = NSUserActivity(activityType: Self.activityType)
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        #if os(iOS)
        activity.isEligibleForPrediction = false
        #endif

        guard configureActivity(activity, for: destination) else {
            LoggingService.shared.debug("[Handoff] Skipping activity for destination (not eligible)", category: .general)
            return
        }

        currentActivity = activity
        activity.becomeCurrent()
        LoggingService.shared.debug("[Handoff] Activity became current: \(activity.title ?? "untitled") - type: \(activity.activityType)", category: .general)
    }

    /// Updates activity with current playback position (call periodically).
    func updatePlaybackTime(_ time: TimeInterval) {
        guard var userInfo = currentActivity?.userInfo else { return }
        userInfo[UserInfoKey.playbackTime] = time
        currentActivity?.userInfo = userInfo
        currentActivity?.needsSave = true
    }

    /// Clears the current activity.
    func invalidateCurrentActivity() {
        if let activity = currentActivity {
            LoggingService.shared.debug("[Handoff] Invalidating activity: \(activity.title ?? "untitled")", category: .general)
            activity.invalidate()
        }
        currentActivity = nil
    }

    // MARK: - Activity Configuration

    /// Configures activity for a destination. Returns false if destination shouldn't support handoff.
    private func configureActivity(_ activity: NSUserActivity, for destination: NavigationDestination) -> Bool {
        var userInfo: [AnyHashable: Any] = [:]

        switch destination {
        case .video(let source, _):
            guard case .id(let videoID) = source else {
                return false
            }
            userInfo[UserInfoKey.destinationType] = DestinationType.video.rawValue
            userInfo[UserInfoKey.videoID] = videoID.videoID
            if let uuid = videoID.uuid {
                userInfo[UserInfoKey.videoUUID] = uuid
            }
            userInfo[UserInfoKey.videoSource] = encodeSource(videoID.source)
            if let time = playerState?.currentTime, time > 0 {
                userInfo[UserInfoKey.playbackTime] = time
            }
            activity.title = playerState?.currentVideo?.title ?? "Video"

        case .channel(let channelID, let source):
            userInfo[UserInfoKey.destinationType] = DestinationType.channel.rawValue
            userInfo[UserInfoKey.channelID] = channelID
            userInfo[UserInfoKey.channelSource] = encodeSource(source)
            activity.title = "Channel"

        case .playlist(let source):
            switch source {
            case .local(let uuid, _):
                userInfo[UserInfoKey.destinationType] = DestinationType.localPlaylist.rawValue
                userInfo[UserInfoKey.localPlaylistUUID] = uuid.uuidString
                activity.title = "Playlist"
            case .remote(let playlistID, _, _):
                userInfo[UserInfoKey.destinationType] = DestinationType.playlist.rawValue
                userInfo[UserInfoKey.playlistID] = playlistID.playlistID
                if let contentSource = playlistID.source {
                    userInfo[UserInfoKey.playlistSource] = encodeSource(contentSource)
                }
                activity.title = "Playlist"
            }

        case .search(let query):
            userInfo[UserInfoKey.destinationType] = DestinationType.search.rawValue
            userInfo[UserInfoKey.searchQuery] = query
            activity.title = "Search: \(query)"

        case .externalVideo(let url):
            userInfo[UserInfoKey.destinationType] = DestinationType.externalVideo.rawValue
            userInfo[UserInfoKey.externalURL] = url.absoluteString
            if let time = playerState?.currentTime, time > 0 {
                userInfo[UserInfoKey.playbackTime] = time
            }
            activity.title = "External Video"

        case .externalChannel(let url):
            userInfo[UserInfoKey.destinationType] = DestinationType.externalChannel.rawValue
            userInfo[UserInfoKey.externalURL] = url.absoluteString
            activity.title = "External Channel"

        case .subscriptionsFeed:
            userInfo[UserInfoKey.destinationType] = DestinationType.subscriptions.rawValue
            activity.title = "Subscriptions"

        case .continueWatching:
            userInfo[UserInfoKey.destinationType] = DestinationType.continueWatching.rawValue
            activity.title = "Continue Watching"

        case .downloads:
            userInfo[UserInfoKey.destinationType] = DestinationType.downloads.rawValue
            activity.title = "Downloads"

        case .history:
            userInfo[UserInfoKey.destinationType] = DestinationType.history.rawValue
            activity.title = "History"

        case .bookmarks:
            userInfo[UserInfoKey.destinationType] = DestinationType.bookmarks.rawValue
            activity.title = "Bookmarks"

        case .playlists:
            userInfo[UserInfoKey.destinationType] = DestinationType.playlists.rawValue
            activity.title = "Playlists"

        case .manageChannels:
            userInfo[UserInfoKey.destinationType] = DestinationType.channels.rawValue
            activity.title = "Channels"

        case .instanceBrowse(let instance, _):
            userInfo[UserInfoKey.destinationType] = DestinationType.instanceBrowse.rawValue
            userInfo[UserInfoKey.instanceURL] = instance.url.absoluteString
            userInfo[UserInfoKey.instanceType] = instance.type.rawValue
            activity.title = instance.displayName

        // Don't create handoff activities for these local-only destinations
        case .settings, .mediaSources, .mediaSource, .mediaBrowser,
             .importSubscriptions, .importPlaylists, .downloadsStorage, .directMedia:
            return false
        }

        activity.userInfo = userInfo
        return true
    }

    // MARK: - Source Encoding/Decoding

    private func encodeSource(_ source: ContentSource) -> [String: Any] {
        switch source {
        case .global(let provider):
            return ["type": "global", "provider": provider]
        case .federated(let provider, let instance):
            return ["type": "federated", "provider": provider, "instance": instance.absoluteString]
        case .extracted(let extractor, let originalURL):
            return ["type": "extracted", "extractor": extractor, "originalURL": originalURL.absoluteString]
        }
    }

    private func decodeSource(_ dict: [String: Any]) -> ContentSource? {
        guard let type = dict["type"] as? String else { return nil }

        switch type {
        case "global":
            guard let provider = dict["provider"] as? String else { return nil }
            return .global(provider: provider)
        case "federated":
            guard let provider = dict["provider"] as? String,
                  let instanceStr = dict["instance"] as? String,
                  let instance = URL(string: instanceStr) else { return nil }
            return .federated(provider: provider, instance: instance)
        case "extracted":
            guard let extractor = dict["extractor"] as? String,
                  let urlStr = dict["originalURL"] as? String,
                  let url = URL(string: urlStr) else { return nil }
            return .extracted(extractor: extractor, originalURL: url)
        default:
            return nil
        }
    }

    // MARK: - Activity Restoration

    /// Restores navigation from a received activity.
    /// Returns the destination and optional playback time.
    func restoreDestination(from activity: NSUserActivity) -> (NavigationDestination, TimeInterval?)? {
        guard activity.activityType == Self.activityType,
              let userInfo = activity.userInfo,
              let typeString = userInfo[UserInfoKey.destinationType] as? String,
              let destType = DestinationType(rawValue: typeString) else {
            return nil
        }

        let playbackTime = userInfo[UserInfoKey.playbackTime] as? TimeInterval

        switch destType {
        case .video:
            guard let videoID = userInfo[UserInfoKey.videoID] as? String,
                  let sourceDict = userInfo[UserInfoKey.videoSource] as? [String: Any],
                  let source = decodeSource(sourceDict) else { return nil }
            let uuid = userInfo[UserInfoKey.videoUUID] as? String
            return (.video(.id(VideoID(source: source, videoID: videoID, uuid: uuid))), playbackTime)

        case .channel:
            guard let channelID = userInfo[UserInfoKey.channelID] as? String,
                  let sourceDict = userInfo[UserInfoKey.channelSource] as? [String: Any],
                  let source = decodeSource(sourceDict) else { return nil }
            return (.channel(channelID, source), nil)

        case .playlist:
            guard let playlistID = userInfo[UserInfoKey.playlistID] as? String else { return nil }
            let source: ContentSource?
            if let sourceDict = userInfo[UserInfoKey.playlistSource] as? [String: Any] {
                source = decodeSource(sourceDict)
            } else {
                source = nil
            }
            return (.playlist(.remote(PlaylistID(source: source, playlistID: playlistID), instance: nil)), nil)

        case .localPlaylist:
            guard let uuidString = userInfo[UserInfoKey.localPlaylistUUID] as? String,
                  let uuid = UUID(uuidString: uuidString) else { return nil }
            return (.playlist(.local(uuid)), nil)

        case .search:
            guard let query = userInfo[UserInfoKey.searchQuery] as? String else { return nil }
            return (.search(query), nil)

        case .externalVideo:
            guard let urlString = userInfo[UserInfoKey.externalURL] as? String,
                  let url = URL(string: urlString) else { return nil }
            return (.externalVideo(url), playbackTime)

        case .externalChannel:
            guard let urlString = userInfo[UserInfoKey.externalURL] as? String,
                  let url = URL(string: urlString) else { return nil }
            return (.externalChannel(url), nil)

        case .subscriptions:
            return (.subscriptionsFeed, nil)
        case .continueWatching:
            return (.continueWatching, nil)
        case .downloads:
            return (.downloads, nil)
        case .history:
            return (.history, nil)
        case .bookmarks:
            return (.bookmarks, nil)
        case .playlists:
            return (.playlists, nil)
        case .channels:
            return (.manageChannels, nil)
        case .instanceBrowse:
            guard let urlString = userInfo[UserInfoKey.instanceURL] as? String,
                  let url = URL(string: urlString),
                  let typeString = userInfo[UserInfoKey.instanceType] as? String,
                  let instanceType = InstanceType(rawValue: typeString) else { return nil }
            let instance = Instance(type: instanceType, url: url)
            return (.instanceBrowse(instance), nil)
        }
    }
}
