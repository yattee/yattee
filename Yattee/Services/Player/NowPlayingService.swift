//
//  NowPlayingService.swift
//  Yattee
//
//  Manages Now Playing info for Control Center and Lock Screen.
//

import Foundation
import MediaPlayer
import AVFoundation

#if os(iOS) || os(tvOS)
import UIKit
typealias NowPlayingImage = UIImage
#elseif os(macOS)
import AppKit
typealias NowPlayingImage = NSImage
#endif

/// Service for updating system Now Playing info (Control Center, Lock Screen).
@MainActor
final class NowPlayingService {
    // MARK: - Properties

    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()

    private var currentVideo: Video?
    private var artworkImage: NowPlayingImage?

    weak var playerService: PlayerService?
    weak var deArrowBrandingProvider: DeArrowBrandingProvider?
    weak var settingsManager: SettingsManager?
    weak var playerControlsLayoutService: PlayerControlsLayoutService?

    // MARK: - Initialization

    init() {
        configureRemoteCommands()
    }

    // MARK: - Public Methods

    /// Updates Now Playing info for a video.
    func updateNowPlaying(
        video: Video,
        currentTime: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool
    ) {
        currentVideo = video

        // Use DeArrow title if available, otherwise use original title
        let title = deArrowBrandingProvider?.title(for: video) ?? video.title

        // Determine if this is a live stream
        let isLive = video.isLive

        // Build the Now Playing info dictionary with all properties needed for tvOS
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: video.author.name,
            MPNowPlayingInfoPropertyIsLiveStream: isLive,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackQueueCount: 1,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: 0,
            MPMediaItemPropertyMediaType: MPMediaType.anyVideo.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]

        // Only add duration for non-live content
        if !isLive && duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }

        // Add artwork if available
        if let artwork = artworkImage {
            #if os(iOS) || os(tvOS)
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
                boundsSize: artwork.size
            ) { _ in artwork }
            #elseif os(macOS)
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
                boundsSize: artwork.size
            ) { _ in artwork }
            #endif
        }

        LoggingService.shared.debug(
            "Setting Now Playing info with \(nowPlayingInfo.count) keys: \(nowPlayingInfo.keys.joined(separator: ", "))",
            category: .player
        )

        infoCenter.nowPlayingInfo = nowPlayingInfo

        // Only set playbackState on non-tvOS platforms.
        // tvOS requires com.apple.mediaremote.set-playback-state entitlement which is restricted.
        // The MPNowPlayingInfoPropertyPlaybackRate property is sufficient to indicate state.
        #if !os(tvOS)
        infoCenter.playbackState = isPlaying ? .playing : .paused
        #endif

        LoggingService.shared.debug(
            "Updated Now Playing: \(video.id.id) - title: \(title), duration: \(duration), time: \(currentTime), playing: \(isPlaying), live: \(isLive)",
            category: .player
        )
    }

    /// Updates playback time without changing other metadata.
    func updatePlaybackTime(currentTime: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
        guard var info = infoCenter.nowPlayingInfo else { return }

        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        infoCenter.nowPlayingInfo = info

        #if !os(tvOS)
        infoCenter.playbackState = isPlaying ? .playing : .paused
        #endif
    }

    /// Updates playback rate (playing/paused state).
    /// Also updates elapsed time to ensure Now Playing info persists in Control Center.
    func updatePlaybackRate(isPlaying: Bool, currentTime: TimeInterval? = nil) {
        LoggingService.shared.debug(
            "updatePlaybackRate called: isPlaying=\(isPlaying), currentTime=\(currentTime ?? -1)",
            category: .player
        )

        guard var info = infoCenter.nowPlayingInfo else {
            LoggingService.shared.warning(
                "updatePlaybackRate: nowPlayingInfo is nil, cannot update",
                category: .player
            )
            return
        }

        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        // When pausing, we must also update the elapsed time to ensure iOS
        // properly preserves the Now Playing info in Control Center.
        // Without this, iOS may clear the metadata when playback stops.
        if let time = currentTime {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
        }

        infoCenter.nowPlayingInfo = info

        #if !os(tvOS)
        infoCenter.playbackState = isPlaying ? .playing : .paused
        #endif

        LoggingService.shared.debug(
            "updatePlaybackRate completed: rate=\(isPlaying ? 1.0 : 0.0), info keys=\(info.keys.count)",
            category: .player
        )
    }

    /// Immediately updates elapsed playback time (used for seek feedback in Control Center).
    func updatePlaybackTimeImmediate(_ time: TimeInterval) {
        guard var info = infoCenter.nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
        infoCenter.nowPlayingInfo = info
    }

    /// Loads artwork from local path (for offline playback) or URL and updates Now Playing info.
    /// - Parameters:
    ///   - url: Remote URL to fetch artwork from (used as fallback if localPath fails)
    ///   - localPath: Local file path for offline artwork (tried first if provided)
    func loadArtwork(from url: URL?, localPath: URL? = nil) async {
        // 1. Try local path first (for offline playback of downloaded videos)
        if let localPath {
            do {
                let data = try Data(contentsOf: localPath)
                #if os(iOS) || os(tvOS)
                if let image = UIImage(data: data) {
                    artworkImage = image
                    updateNowPlayingWithCurrentArtwork()
                    LoggingService.shared.debug(
                        "Loaded artwork from local path: \(localPath.lastPathComponent)",
                        category: .player
                    )
                    return
                }
                #elseif os(macOS)
                if let image = NSImage(data: data) {
                    artworkImage = image
                    updateNowPlayingWithCurrentArtwork()
                    LoggingService.shared.debug(
                        "Loaded artwork from local path: \(localPath.lastPathComponent)",
                        category: .player
                    )
                    return
                }
                #endif
            } catch {
                LoggingService.shared.debug(
                    "Local artwork not available, falling back to network: \(error.localizedDescription)",
                    category: .player
                )
            }
        }

        // 2. Fall back to network fetch
        guard let url else {
            artworkImage = nil
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            #if os(iOS) || os(tvOS)
            artworkImage = UIImage(data: data)
            #elseif os(macOS)
            artworkImage = NSImage(data: data)
            #endif

            updateNowPlayingWithCurrentArtwork()
        } catch {
            LoggingService.shared.error(
                "Failed to load artwork: \(error.localizedDescription)",
                category: .player
            )
        }
    }

    /// Helper to update Now Playing info with current artwork
    private func updateNowPlayingWithCurrentArtwork() {
        if let video = currentVideo,
           let info = infoCenter.nowPlayingInfo,
           let duration = info[MPMediaItemPropertyPlaybackDuration] as? TimeInterval,
           let currentTime = info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval,
           let rate = info[MPNowPlayingInfoPropertyPlaybackRate] as? Double {
            updateNowPlaying(
                video: video,
                currentTime: currentTime,
                duration: duration,
                isPlaying: rate > 0
            )
        }
    }

    /// Clears Now Playing info.
    func clearNowPlaying() {
        infoCenter.nowPlayingInfo = nil

        #if !os(tvOS)
        infoCenter.playbackState = .stopped
        #endif

        currentVideo = nil
        artworkImage = nil

        LoggingService.shared.debug("Cleared Now Playing info", category: .player)
    }

    // MARK: - Remote Commands

    /// Removes all existing command targets to allow reconfiguration.
    private func removeAllTargets() {
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
    }

    /// Configures remote commands based on current settings.
    /// Call this method when settings change to reconfigure the commands.
    func configureRemoteCommands() {
        // Remove existing targets to prevent duplicate handlers
        removeAllTargets()

        // Read settings from active preset's cached global settings
        if let layoutService = playerControlsLayoutService {
            Task {
                let layout = await layoutService.activeLayout()
                await MainActor.run {
                    self.configureRemoteCommandsWithSettings(
                        mode: layout.globalSettings.systemControlsMode,
                        duration: layout.globalSettings.systemControlsSeekDuration
                    )
                }
            }
            // Return early - async task will call configureRemoteCommandsWithSettings
            return
        }
        // Fallback to cached defaults if no layout service
        let mode = GlobalLayoutSettings.cached.systemControlsMode
        let duration = GlobalLayoutSettings.cached.systemControlsSeekDuration

        configureRemoteCommandsWithSettings(mode: mode, duration: duration)
    }

    /// Configures remote commands with the specified settings.
    /// - Parameters:
    ///   - mode: The system controls mode (seek or skip track).
    ///   - duration: The seek duration when mode is .seek.
    private func configureRemoteCommandsWithSettings(mode: SystemControlsMode, duration: SystemControlsSeekDuration) {
        // Remove existing targets (in case called from async path)
        removeAllTargets()

        // Play
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            LoggingService.shared.debug("Remote playCommand received", category: .player)
            guard let self else {
                LoggingService.shared.warning("Remote playCommand: self is nil", category: .player)
                return .commandFailed
            }
            self.playerService?.resume()
            return .success
        }

        // Pause
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            LoggingService.shared.debug("Remote pauseCommand received", category: .player)
            guard let self else {
                LoggingService.shared.warning("Remote pauseCommand: self is nil", category: .player)
                return .commandFailed
            }
            self.playerService?.pause()
            return .success
        }

        // Toggle play/pause
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            LoggingService.shared.debug("Remote togglePlayPauseCommand received", category: .player)
            guard let self else {
                LoggingService.shared.warning("Remote togglePlayPauseCommand: self is nil", category: .player)
                return .commandFailed
            }
            self.playerService?.togglePlayPause()
            return .success
        }

        // Configure skip commands based on mode
        let seekEnabled = mode == .seek
        commandCenter.skipForwardCommand.isEnabled = seekEnabled
        commandCenter.skipBackwardCommand.isEnabled = seekEnabled

        if seekEnabled {
            commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: duration.timeInterval)]
            commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: duration.timeInterval)]

            // Skip forward
            commandCenter.skipForwardCommand.addTarget { [weak self] event in
                guard let self,
                      let skipEvent = event as? MPSkipIntervalCommandEvent else {
                    return .commandFailed
                }
                // Immediately update Now Playing time to prevent UI jumping
                if let currentTime = self.infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval,
                   let videoDuration = self.infoCenter.nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] as? TimeInterval {
                    let newTime = min(currentTime + skipEvent.interval, videoDuration)
                    self.updatePlaybackTimeImmediate(newTime)
                }
                Task {
                    self.playerService?.seekForward(by: skipEvent.interval)
                }
                return .success
            }

            // Skip backward
            commandCenter.skipBackwardCommand.addTarget { [weak self] event in
                guard let self,
                      let skipEvent = event as? MPSkipIntervalCommandEvent else {
                    return .commandFailed
                }
                // Immediately update Now Playing time to prevent UI jumping
                if let currentTime = self.infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval {
                    let newTime = max(currentTime - skipEvent.interval, 0)
                    self.updatePlaybackTimeImmediate(newTime)
                }
                Task {
                    self.playerService?.seekBackward(by: skipEvent.interval)
                }
                return .success
            }
        }

        // Seek (scrubbing) - always enabled
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            // Immediately update Now Playing time to prevent UI jumping back
            self.updatePlaybackTimeImmediate(positionEvent.positionTime)
            Task {
                await self.playerService?.seek(to: positionEvent.positionTime)
            }
            return .success
        }

        // Next/Previous track - always enabled
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task {
                await self.playerService?.playNext()
            }
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task {
                await self.playerService?.playPrevious()
            }
            return .success
        }

        LoggingService.shared.debug(
            "Remote commands configured: mode=\(mode), seekDuration=\(duration.rawValue)s",
            category: .player
        )
    }
}
