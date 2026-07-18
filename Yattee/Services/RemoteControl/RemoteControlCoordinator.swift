//
//  RemoteControlCoordinator.swift
//  Yattee
//
//  Coordinates remote control between network service and player.
//

import Foundation
import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Coordinates remote control functionality between the local network service and player.
@MainActor
@Observable
final class RemoteControlCoordinator {

    // MARK: - Constants

    private static let enabledKey = "RemoteControl.Enabled"

    // MARK: - Remote Play Toast

    /// Toast ID for the current remote play operation (for updating status).
    private var remotePlayToastID: UUID?

    /// Device ID we're waiting for state confirmation from.
    private var pendingRemotePlayDeviceID: String?

    /// Video ID we're waiting for (to ignore stale state updates).
    private var pendingRemotePlayVideoID: String?

    /// Whether we're waiting to pause local playback after remote device starts playing (for "Move to" feature).
    private var pendingMoveOperation: Bool = false

    /// Clears any pending remote play state. Called when starting a new operation or on failure.
    private func clearPendingRemotePlay() {
        if let toastID = remotePlayToastID {
            toastManager?.dismiss(id: toastID)
        }
        remotePlayToastID = nil
        pendingRemotePlayDeviceID = nil
        pendingRemotePlayVideoID = nil
        pendingMoveOperation = false
    }

    // MARK: - Public State

    /// Whether remote control is enabled. Persisted across app launches.
    var isEnabled: Bool = false {
        didSet {
            if isEnabled != oldValue {
                UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
                if isEnabled {
                    start()
                } else {
                    stop()
                }
            }
        }
    }

    /// Discovered devices on the local network.
    var discoveredDevices: [DiscoveredDevice] {
        networkService.discoveredDevices
    }

    /// Device IDs we're currently controlling.
    private(set) var controllingDevices: Set<String> = []

    /// Last known state of devices we're controlling (keyed by device ID).
    private(set) var remoteDeviceStates: [String: RemotePlayerState] = [:]

    /// Whether we're being controlled by another device.
    private(set) var isBeingControlled: Bool = false

    /// The device that's controlling us, if any.
    private(set) var controllingDevice: DiscoveredDevice?

    /// This device's name for display.
    var deviceName: String {
        get { networkService.deviceName }
        set { networkService.deviceName = newValue }
    }

    /// This device's ID.
    var deviceID: String {
        networkService.deviceID
    }

    // MARK: - Dependencies

    private let networkService: LocalNetworkService
    private weak var playerService: PlayerService?
    private weak var contentService: ContentService?
    private weak var instancesManager: InstancesManager?
    private weak var navigationCoordinator: NavigationCoordinator?
    private weak var mediaSourcesManager: MediaSourcesManager?
    private weak var toastManager: ToastManager?
    private weak var settingsManager: SettingsManager?

    // MARK: - Logging Helpers

    /// Log to LoggingService for comprehensive debugging.
    private func rcLog(_ operation: String, _ message: String, isWarning: Bool = false, isError: Bool = false, details: String? = nil) {
        let fullMessage = "[RemoteControl] \(operation) - \(message)"
        if isError {
            LoggingService.shared.logRemoteControlError(fullMessage, error: nil)
        } else if isWarning {
            LoggingService.shared.logRemoteControlWarning(fullMessage, details: details)
        } else {
            LoggingService.shared.logRemoteControl(fullMessage, details: details)
        }
    }

    /// Log debug-level message. Only logs if verbose remote control logging is enabled.
    private func rcDebug(_ operation: String, _ message: String) {
        guard UserDefaults.standard.bool(forKey: "verboseRemoteControlLogging") else { return }
        let fullMessage = "[RemoteControl] \(operation) - \(message)"
        LoggingService.shared.logRemoteControlDebug(fullMessage)
    }

    /// Task for listening to incoming commands.
    private var commandListenerTask: Task<Void, Never>?

    /// Task for state broadcast timer.
    private var stateBroadcastTask: Task<Void, Never>?

    /// Task for observing incognito mode changes.
    private var incognitoObserverTask: Task<Void, Never>?

    /// Last state that was broadcast (for change detection).
    private var lastBroadcastState: RemotePlayerState?

    // MARK: - Initialization

    init(networkService: LocalNetworkService) {
        self.networkService = networkService
    }

    /// Set the player service reference (called after AppEnvironment is set up).
    func setPlayerService(_ playerService: PlayerService) {
        self.playerService = playerService
    }

    /// Set the content service reference.
    func setContentService(_ contentService: ContentService) {
        self.contentService = contentService
    }

    /// Set the instances manager reference.
    func setInstancesManager(_ instancesManager: InstancesManager) {
        self.instancesManager = instancesManager
    }

    /// Set the navigation coordinator reference.
    func setNavigationCoordinator(_ navigationCoordinator: NavigationCoordinator) {
        self.navigationCoordinator = navigationCoordinator
    }

    /// Set the media sources manager reference.
    func setMediaSourcesManager(_ manager: MediaSourcesManager) {
        self.mediaSourcesManager = manager
    }

    /// Set the toast manager reference.
    func setToastManager(_ manager: ToastManager) {
        self.toastManager = manager
    }

    /// Set the settings manager reference and start observing incognito mode.
    func setSettingsManager(_ manager: SettingsManager) {
        self.settingsManager = manager
        startIncognitoObserver()
    }

    /// Restore persisted enabled state. Call after all services are set up.
    func restoreEnabledState() {
        let wasEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        if wasEnabled {
            rcLog("LIFECYCLE", "Restoring remote control enabled state from UserDefaults")
            isEnabled = true
        }
    }

    // MARK: - Lifecycle

    /// Start remote control services (discovery + hosting).
    /// Does nothing if incognito mode is enabled - remote control is completely disabled in incognito.
    private func start() {
        let isIncognito = settingsManager?.incognitoModeEnabled ?? false
        
        // Remote control is completely disabled in incognito mode
        if isIncognito {
            rcLog("LIFECYCLE", "Remote control disabled (incognito mode enabled)")
            return
        }
        
        rcLog("LIFECYCLE", "Starting remote control services", details: "deviceName=\(networkService.deviceName), deviceID=\(networkService.deviceID)")

        networkService.startHosting()
        networkService.startDiscovery()

        // Reset the commands stream so the new listener Task gets a fresh stream
        // This is needed because AsyncStream doesn't work well with cancelled consumers
        networkService.resetCommandsStream()

        startCommandListener()
        startStateBroadcast()

        rcLog("LIFECYCLE", "Remote control services started")
    }

    /// Stop all remote control services.
    private func stop() {
        rcLog("LIFECYCLE", "Stopping remote control services", details: "controlling=\(controllingDevices.count) devices")

        commandListenerTask?.cancel()
        commandListenerTask = nil

        stateBroadcastTask?.cancel()
        stateBroadcastTask = nil

        networkService.disconnectAll()
        networkService.stopDiscovery()
        networkService.stopHosting()

        controllingDevices.removeAll()
        isBeingControlled = false
        controllingDevice = nil

        rcLog("LIFECYCLE", "Remote control services stopped")
    }

    /// Start observing incognito mode changes.
    private func startIncognitoObserver() {
        incognitoObserverTask?.cancel()
        incognitoObserverTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let settings = self.settingsManager else { break }

                let wasIncognito = settings.incognitoModeEnabled
                _ = withObservationTracking {
                    settings.incognitoModeEnabled
                } onChange: { }

                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { break }

                let isIncognito = settings.incognitoModeEnabled
                if isIncognito != wasIncognito {
                    self.handleIncognitoModeChanged(isIncognito: isIncognito)
                }
            }
        }
    }

    /// Handle incognito mode changes by disabling remote control.
    /// Remote control is completely disabled in incognito mode to ensure the device is invisible.
    /// When incognito is disabled, user must manually re-enable remote control.
    private func handleIncognitoModeChanged(isIncognito: Bool) {
        if isIncognito && isEnabled {
            rcLog("LIFECYCLE", "Incognito enabled - disabling remote control")
            isEnabled = false  // This triggers stop() via didSet
        }
        // When incognito is disabled, user must manually re-enable remote control
    }

    /// Handle app scene phase changes - refresh services when returning to foreground.
    func handleScenePhase(_ phase: ScenePhase) {
        guard isEnabled else { return }

        switch phase {
        case .active:
            let isIncognito = settingsManager?.incognitoModeEnabled ?? false
            rcLog("LIFECYCLE", "App became active - refreshing services", details: "incognito=\(isIncognito)")
            if !isIncognito {
                networkService.refreshServices()
            } else {
                networkService.refreshDiscoveryOnly()
            }
        case .background:
            #if os(iOS) || os(tvOS)
            let hideWhenBackgrounded = settingsManager?.remoteControlHideWhenBackgrounded ?? true
            let isIncognito = settingsManager?.incognitoModeEnabled ?? false
            // Only stop hosting if we were actually hosting (not incognito)
            if hideWhenBackgrounded && !isIncognito {
                rcLog("LIFECYCLE", "App entering background - stopping hosting to hide from remote devices")
                networkService.stopHosting()
            } else {
                rcLog("LIFECYCLE", "App entering background", details: "hideWhenBackgrounded=\(hideWhenBackgrounded), incognito=\(isIncognito)")
            }
            #else
            rcLog("LIFECYCLE", "App entering background")
            #endif
        case .inactive:
            rcDebug("LIFECYCLE", "App became inactive")
        @unknown default:
            break
        }
    }

    // MARK: - Connection Management

    /// Connect to a device to control it.
    func connect(to device: DiscoveredDevice) async throws {
        rcLog("CONTROL", "[\(device.name)] Connecting to control device")
        try await networkService.connect(to: device)
        controllingDevices.insert(device.id)
        rcLog("CONTROL", "[\(device.name)] Connected, requesting initial state")

        // Request current state from the device
        try await networkService.send(command: .requestState, to: device.id)
    }

    /// Disconnect from a device.
    func disconnect(from device: DiscoveredDevice) {
        rcLog("CONTROL", "[\(device.name)] Disconnecting from device")
        networkService.disconnect(from: device.id)
        controllingDevices.remove(device.id)
    }

    // MARK: - Command Sending

    /// Send a command to a specific device.
    func sendCommand(_ command: RemoteControlCommand, to device: DiscoveredDevice) async {
        let commandDesc = String(describing: command).prefix(50)
        do {
            try await networkService.send(command: command, to: device.id)
            rcLog("COMMAND", "[\(device.name)] Sent: \(commandDesc)")
        } catch {
            rcLog("COMMAND", "[\(device.name)] Failed to send \(commandDesc): \(error.localizedDescription)", isError: true)
        }
    }

    /// Send a command to all connected devices.
    func broadcastCommand(_ command: RemoteControlCommand) async {
        let commandDesc = String(describing: command).prefix(50)
        rcDebug("COMMAND", "Broadcasting: \(commandDesc)")
        await networkService.broadcast(command: command)
    }

    // MARK: - Convenience Commands

    /// Send play command to a device.
    func play(on device: DiscoveredDevice) async {
        await sendCommand(.play, to: device)
    }

    /// Send pause command to a device.
    func pause(on device: DiscoveredDevice) async {
        await sendCommand(.pause, to: device)
    }

    /// Send toggle play/pause command to a device.
    func togglePlayPause(on device: DiscoveredDevice) async {
        await sendCommand(.togglePlayPause, to: device)
    }

    /// Send seek command to a device.
    func seek(to time: TimeInterval, on device: DiscoveredDevice) async {
        await sendCommand(.seek(time: time), to: device)
    }

    /// Send volume command to a device.
    func setVolume(_ volume: Float, on device: DiscoveredDevice) async {
        await sendCommand(.setVolume(volume), to: device)
    }

    /// Send mute command to a device.
    func setMuted(_ muted: Bool, on device: DiscoveredDevice) async {
        await sendCommand(.setMuted(muted), to: device)
    }

    /// Send playback rate command to a device.
    func setRate(_ rate: Float, on device: DiscoveredDevice) async {
        await sendCommand(.setRate(rate), to: device)
    }

    /// Load a video on a device.
    /// - Parameters:
    ///   - videoID: The video ID to load.
    ///   - videoTitle: Optional video title for logging.
    ///   - instanceURL: The instance URL to use for loading the video.
    ///   - startTime: Optional start time to seek to after loading.
    ///   - pauseLocalPlayback: If true, pause local playback when remote device starts playing (for "Move to" feature).
    ///   - device: The device to load the video on.
    func loadVideo(videoID: String, videoTitle: String? = nil, instanceURL: String?, startTime: TimeInterval? = nil, pauseLocalPlayback: Bool = false, on device: DiscoveredDevice) async {
        rcLog("REMOTEPLAY", "[\(device.name)] Starting remote play", details: "videoID=\(videoID), instance=\(instanceURL ?? "default"), startTime=\(startTime ?? 0), pauseLocal=\(pauseLocalPlayback)")

        // Clear any stale pending state from previous timed-out operations
        clearPendingRemotePlay()

        // First, verify we have a working connection to the device
        // This prevents sending into dead connections that look "ready"
        rcLog("REMOTEPLAY", "[\(device.name)] Verifying connection before send...")
        let connectionVerified = await networkService.ensureConnection(to: device.id)

        guard connectionVerified else {
            rcLog("REMOTEPLAY", "[\(device.name)] Connection verification FAILED", isError: true)
            toastManager?.show(
                category: .remoteControl,
                title: String(localized: "toast.remote.connectionFailed.title"),
                subtitle: device.name,
                icon: "exclamationmark.triangle.fill",
                iconColor: .orange,
                autoDismissDelay: 3.0
            )
            return
        }

        rcLog("REMOTEPLAY", "[\(device.name)] Connection verified, sending loadVideo command")

        // Show persistent toast for sending status
        let toastID = toastManager?.show(
            category: .remoteControl,
            title: String(localized: "toast.remote.playingOn.title"),
            subtitle: device.name,
            icon: nil, // Shows ProgressView for remoteControl category
            iconColor: nil,
            autoDismissDelay: 10.0, // Timeout if no response
            isPersistent: true
        )
        remotePlayToastID = toastID
        pendingRemotePlayDeviceID = device.id
        pendingRemotePlayVideoID = videoID
        pendingMoveOperation = pauseLocalPlayback

        // For move operations, use handshake protocol: remote prepares but waits for play command
        let awaitPlayCommand = pauseLocalPlayback
        await sendCommand(.loadVideo(videoID: videoID, instanceURL: instanceURL, startTime: startTime, awaitPlayCommand: awaitPlayCommand), to: device)
        rcLog("REMOTEPLAY", "[\(device.name)] loadVideo command sent, waiting for state update...")
    }

    /// Close the current video on a device.
    func closeVideo(on device: DiscoveredDevice) async {
        await sendCommand(.closeVideo, to: device)
    }

    /// Toggle fullscreen on a device.
    func toggleFullscreen(on device: DiscoveredDevice) async {
        await sendCommand(.toggleFullscreen, to: device)
    }

    /// Play next video in queue on a device.
    func playNext(on device: DiscoveredDevice) async {
        await sendCommand(.playNext, to: device)
    }

    /// Play previous video in history on a device.
    func playPrevious(on device: DiscoveredDevice) async {
        await sendCommand(.playPrevious, to: device)
    }

    // MARK: - State Updates

    /// Update the network service with current player state.
    func updatePlayerState() {
        guard let playerService else { return }

        let state = playerService.state
        networkService.updateAdvertisement(
            videoTitle: state.currentVideo?.title,
            channelName: state.currentVideo?.author.name,
            thumbnailURL: state.currentVideo?.bestThumbnail?.url,
            isPlaying: state.playbackState == .playing
        )
    }

    /// Get current player state for sharing.
    func currentRemoteState() -> RemotePlayerState {
        guard let playerService else { return .idle }

        let state = playerService.state

        // Compute fullscreen state (same logic as shouldShowFullscreenButton in PlayerControlsActions)
        #if os(iOS)
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let screenBounds = UIScreen.main.bounds
        let isWideScreenLayout = screenBounds.width > screenBounds.height
        // iPad in widescreen = can't force rotation, so fullscreen toggle not available
        let canToggleFullscreen = !(isIPad && isWideScreenLayout) && state.currentVideo != nil
        let isFullscreen = isWideScreenLayout
        #else
        let canToggleFullscreen = false
        let isFullscreen = false
        #endif

        return RemotePlayerState(
            videoID: state.currentVideo?.id.videoID,
            videoTitle: state.currentVideo?.title,
            channelName: state.currentVideo?.author.name,
            thumbnailURL: state.currentVideo?.bestThumbnail?.url,
            currentTime: state.currentTime,
            duration: state.duration,
            isPlaying: state.playbackState == .playing,
            rate: Float(state.rate.rawValue),
            volume: state.volume,
            isMuted: state.isMuted,
            volumeMode: GlobalLayoutSettings.cached.volumeMode.rawValue,
            isFullscreen: isFullscreen,
            canToggleFullscreen: canToggleFullscreen,
            hasPrevious: state.hasPrevious,
            hasNext: state.hasNext
        )
    }

    /// Broadcasts the current state to all connected devices.
    /// Call this when settings change that affect remote control behavior (e.g., volume mode).
    func broadcastStateUpdate() {
        Task {
            let state = currentRemoteState()
            await networkService.broadcast(command: .stateUpdate(state))
        }
    }

    // MARK: - Command Listening

    private func startCommandListener() {
        commandListenerTask = Task { [weak self] in
            guard let self else { return }

            for await message in networkService.incomingCommands {
                await self.handleIncomingCommand(message)
            }
        }
    }

    private func handleIncomingCommand(_ message: RemoteControlMessage) async {
        let senderName = message.senderDeviceName ?? message.senderDeviceID
        let commandDesc = String(describing: message.command).prefix(80)
        rcLog("HANDLE", "[\(senderName)] Handling: \(commandDesc)")

        // Track that we're being controlled
        if case .stateUpdate = message.command {
            // State updates are responses, not control
        } else if case .requestState = message.command {
            // Don't respond to state requests in incognito mode - device should be invisible
            let isIncognito = settingsManager?.incognitoModeEnabled ?? false
            guard !isIncognito else {
                rcLog("HANDLE", "[\(senderName)] Ignoring state request (incognito mode)")
                return
            }
            // Request for state, respond with current state - do this in background to not block command processing
            rcLog("HANDLE", "[\(senderName)] Sending state response")
            let state = currentRemoteState()
            let deviceID = message.senderDeviceID
            Task {
                do {
                    try await networkService.send(
                        command: .stateUpdate(state),
                        to: deviceID
                    )
                    self.rcDebug("HANDLE", "[\(senderName)] State response sent")
                } catch {
                    self.rcLog("HANDLE", "[\(senderName)] Failed to send state: \(error.localizedDescription)", isError: true)
                }
            }
        } else {
            // Being controlled
            isBeingControlled = true
            controllingDevice = discoveredDevices.first { $0.id == message.senderDeviceID }
            rcLog("HANDLE", "[\(senderName)] Now being controlled by this device")
        }

        // Handle the command
        switch message.command {
        case .play:
            rcDebug("HANDLE", "[\(senderName)] Executing: play")
            playerService?.resume()

        case .pause:
            rcDebug("HANDLE", "[\(senderName)] Executing: pause")
            playerService?.pause()

        case .togglePlayPause:
            rcDebug("HANDLE", "[\(senderName)] Executing: togglePlayPause")
            playerService?.togglePlayPause()

        case .seek(let time):
            rcDebug("HANDLE", "[\(senderName)] Executing: seek to \(time)s")
            await playerService?.seek(to: time)

        case .setVolume(let volume):
            // Only handle volume commands when in-app (MPV) volume mode
            guard GlobalLayoutSettings.cached.volumeMode == .mpv else {
                rcDebug("HANDLE", "[\(senderName)] Ignoring setVolume - system volume mode active")
                return
            }
            if let backend = playerService?.currentBackend {
                rcDebug("HANDLE", "[\(senderName)] Executing: setVolume to \(volume)")
                backend.volume = volume
                playerService?.state.volume = volume
            } else {
                rcLog("HANDLE", "[\(senderName)] Cannot set volume - no player backend", isError: true)
            }

        case .setMuted(let muted):
            // Only handle mute commands when in-app (MPV) volume mode
            guard GlobalLayoutSettings.cached.volumeMode == .mpv else {
                rcDebug("HANDLE", "[\(senderName)] Ignoring setMuted - system volume mode active")
                return
            }
            if let backend = playerService?.currentBackend {
                rcDebug("HANDLE", "[\(senderName)] Executing: setMuted to \(muted)")
                backend.isMuted = muted
                playerService?.state.isMuted = muted
            } else {
                rcLog("HANDLE", "[\(senderName)] Cannot set muted - no player backend", isError: true)
            }

        case .setRate(let rate):
            rcDebug("HANDLE", "[\(senderName)] Executing: setRate to \(rate)")
            playerService?.currentBackend?.rate = rate
            if let playbackRate = PlaybackRate(rawValue: Double(rate)) {
                playerService?.state.rate = playbackRate
            }

        case .loadVideo(let videoID, let instanceURLString, let startTime, let awaitPlayCommand):
            rcLog("HANDLE", "[\(senderName)] Executing: loadVideo", details: "videoID=\(videoID), instance=\(instanceURLString ?? "default"), startTime=\(startTime ?? 0), awaitPlay=\(awaitPlayCommand ?? false)")
            // Show toast indicating remote video opening
            if let deviceName = controllingDevice?.name {
                toastManager?.show(
                    category: .remoteControl,
                    title: String(localized: "toast.remote.openingVideo.title"),
                    subtitle: deviceName,
                    icon: "arrow.down.circle.fill",
                    iconColor: .blue,
                    autoDismissDelay: 5.0
                )
            }
            await handleLoadVideo(videoID: videoID, instanceURLString: instanceURLString, startTime: startTime, awaitPlayCommand: awaitPlayCommand ?? false, senderDeviceID: message.senderDeviceID)

        case .closeVideo:
            rcLog("HANDLE", "[\(senderName)] Executing: closeVideo")
            // Collapse the player UI first
            navigationCoordinator?.isPlayerExpanded = false
            // Then stop playback
            playerService?.stop()
            // Send state update after a short delay so the stop has time to complete
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                let state = self.currentRemoteState()
                await self.networkService.broadcast(command: .stateUpdate(state))
            }

        case .toggleFullscreen:
            rcLog("HANDLE", "[\(senderName)] Executing: toggleFullscreen")
            // Trigger fullscreen toggle via navigation coordinator
            navigationCoordinator?.pendingFullscreenToggle += 1
            // Send state update after a short delay so the orientation change has time to complete
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                let state = self.currentRemoteState()
                await self.networkService.broadcast(command: .stateUpdate(state))
            }

        case .playNext:
            rcLog("HANDLE", "[\(senderName)] Executing: playNext")
            await playerService?.playNext()

        case .playPrevious:
            rcLog("HANDLE", "[\(senderName)] Executing: playPrevious")
            await playerService?.playPrevious()

        case .requestState:
            // Already handled above
            break

        case .stateUpdate(let state):
            // This is a response to our requestState - store it for the UI
            remoteDeviceStates[message.senderDeviceID] = state

            // Also update the discovered device list so the device list UI shows current video
            networkService.updateDiscoveredDevicePlaybackState(
                deviceID: message.senderDeviceID,
                videoTitle: state.videoTitle,
                channelName: state.channelName,
                thumbnailURL: state.thumbnailURL,
                isPlaying: state.isPlaying
            )
            rcLog("HANDLE", "[\(senderName)] Received state update", details: "video=\(state.videoTitle ?? "none"), playing=\(state.isPlaying)")

            // Check if we were waiting for loadVideo confirmation
            rcDebug("HANDLE", "Remote play check: pending=\(pendingRemotePlayDeviceID ?? "none"), expected=\(pendingRemotePlayVideoID ?? "none")")
            if let toastID = remotePlayToastID,
               message.senderDeviceID == pendingRemotePlayDeviceID,
               let expectedVideoID = pendingRemotePlayVideoID {
                let senderDevice = discoveredDevices.first { $0.id == message.senderDeviceID }
                let deviceName = senderDevice?.name ?? "device"

                rcDebug("HANDLE", "Remote play state: playing=\(state.isPlaying), videoID=\(state.videoID ?? "nil"), expected=\(expectedVideoID)")

                // Only process if the state is for our expected video (ignore stale updates)
                if let receivedVideoID = state.videoID, receivedVideoID == expectedVideoID {
                    if pendingMoveOperation && !state.isPlaying {
                        // Handshake protocol: remote device is ready but waiting for play command
                        // Pause local playback first, then tell remote to start
                        rcLog("REMOTEPLAY", "[\(deviceName)] Remote ready - pausing local and sending play command")
                        playerService?.pause()

                        // Send play command to remote device
                        if let device = senderDevice {
                            Task {
                                await self.sendCommand(.play, to: device)
                            }
                        }

                        // Update toast to success
                        toastManager?.update(
                            id: toastID,
                            title: String(localized: "toast.remote.playingOnSuccess.title"),
                            subtitle: deviceName,
                            icon: "checkmark.circle.fill",
                            iconColor: .green,
                            autoDismissDelay: 2.0
                        )

                        remotePlayToastID = nil
                        pendingRemotePlayDeviceID = nil
                        pendingRemotePlayVideoID = nil
                        pendingMoveOperation = false
                    } else if state.isPlaying {
                        // Video started playing successfully (normal flow without handshake)
                        rcLog("REMOTEPLAY", "[\(deviceName)] Video started playing SUCCESS")
                        toastManager?.update(
                            id: toastID,
                            title: String(localized: "toast.remote.playingOnSuccess.title"),
                            subtitle: deviceName,
                            icon: "checkmark.circle.fill",
                            iconColor: .green,
                            autoDismissDelay: 2.0
                        )

                        remotePlayToastID = nil
                        pendingRemotePlayDeviceID = nil
                        pendingRemotePlayVideoID = nil
                        pendingMoveOperation = false
                    }
                    // If videoID matches but not playing yet and not a move operation, keep showing loading
                }
                // Ignore state updates with different/nil videoID - they're stale
            }
        }

        // Send state update after handling command
        switch message.command {
        case .stateUpdate:
            // Don't respond to state updates with more state updates
            break
        case .requestState:
            // Already sent above
            break
        case .loadVideo, .closeVideo, .toggleFullscreen:
            // Don't send immediate state update for loadVideo/closeVideo/toggleFullscreen - the state is still changing
            // The periodic state broadcast will send the update once the state settles
            break
        default:
            // Broadcast updated state to all connected peers
            let state = currentRemoteState()
            await networkService.broadcast(command: .stateUpdate(state))
        }
    }

    private func handleLoadVideo(videoID: String, instanceURLString: String?, startTime: TimeInterval? = nil, awaitPlayCommand: Bool = false, senderDeviceID: String? = nil) async {
        rcLog("LOADVIDEO", "Loading video: \(videoID)", details: "startTime=\(startTime ?? 0), awaitPlay=\(awaitPlayCommand)")

        // Check if we're already playing the same video - just seek instead of reloading
        if let currentVideoID = playerService?.state.currentVideo?.id.videoID,
           currentVideoID == videoID {
            rcLog("LOADVIDEO", "Same video already playing - just seeking to \(startTime ?? 0)s")

            if let seekTime = startTime {
                await playerService?.seek(to: seekTime)
            }

            // Send state update to confirm
            let state = currentRemoteState()
            if let senderID = senderDeviceID {
                try? await networkService.send(command: .stateUpdate(state), to: senderID)
            } else {
                await networkService.broadcast(command: .stateUpdate(state))
            }
            return
        }

        // Check if this is a WebDAV video (format: "UUID:path")
        // WebDAV videoIDs start with a UUID followed by colon and path
        let components = videoID.split(separator: ":", maxSplits: 1)
        if components.count == 2,
           let sourceUUID = UUID(uuidString: String(components[0])),
           let mediaSourcesManager,
           let source = mediaSourcesManager.source(byID: sourceUUID) {
            // This is a WebDAV video - play directly
            rcLog("LOADVIDEO", "Detected WebDAV video, loading from source: \(source.name)")
            await handleLoadMediaSourceVideo(
                videoID: videoID,
                path: String(components[1]),
                source: source,
                startTime: startTime,
                awaitPlayCommand: awaitPlayCommand,
                senderDeviceID: senderDeviceID
            )
            return
        }

        // Existing API video loading...
        guard let contentService, let instancesManager else {
            rcLog("LOADVIDEO", "Missing contentService or instancesManager", isError: true)
            return
        }

        let instance: Instance?
        if let urlString = instanceURLString, let url = URL(string: urlString) {
            // First try to find an exact match in configured instances
            if let configuredInstance = instancesManager.instances.first(where: { $0.url == url }) {
                instance = configuredInstance
                rcDebug("LOADVIDEO", "Using configured instance: \(instance?.name ?? "not found")")
            } else {
                // Instance not configured locally - check if it's a PeerTube video
                // PeerTube video IDs are numeric, while YouTube IDs are alphanumeric with dashes/underscores
                let isPeerTubeVideoID = videoID.allSatisfy { $0.isNumber }
                
                if isPeerTubeVideoID {
                    // Create a temporary PeerTube instance for this request
                    rcDebug("LOADVIDEO", "Creating temporary PeerTube instance for: \(url.absoluteString)")
                    instance = Instance(
                        type: .peertube,
                        url: url,
                        name: url.host,
                        isEnabled: true
                    )
                } else {
                    // For YouTube content, any configured instance that supports it works
                    instance = instancesManager.instances.first { $0.isEnabled && $0.isYouTubeInstance }
                    rcDebug("LOADVIDEO", "Using fallback YouTube instance: \(instance?.name ?? "none")")
                }
            }
        } else {
            instance = instancesManager.instances.first { $0.isEnabled }
            rcDebug("LOADVIDEO", "Using default instance: \(instance?.name ?? "none")")
        }

        guard let instance else {
            rcLog("LOADVIDEO", "No instance available to load video", isError: true)
            return
        }

        do {
            rcLog("LOADVIDEO", "Fetching video metadata from \(instance.name ?? "unknown")")
            let video = try await contentService.video(id: videoID, instance: instance)

            if awaitPlayCommand {
                // Handshake protocol: load video, then pause and notify sender we're ready
                rcLog("LOADVIDEO", "Handshake mode: loading video, will pause when ready")
                playerService?.openVideo(video, startTime: startTime)

                // Wait for video to start playing, then pause
                // This gives time for the video to load and seek to position
                try? await Task.sleep(for: .milliseconds(1000))

                // Pause playback - video is loaded and at correct position but not playing
                playerService?.pause()
                rcLog("LOADVIDEO", "Video loaded and paused, ready for handoff")

                // Send state update to let sender know we're ready (isPlaying will be false)
                let state = currentRemoteState()
                rcLog("LOADVIDEO", "Sending ready state to sender", details: "videoID=\(state.videoID ?? "nil"), playing=\(state.isPlaying)")
                if let senderID = senderDeviceID {
                    try? await networkService.send(command: .stateUpdate(state), to: senderID)
                } else {
                    await networkService.broadcast(command: .stateUpdate(state))
                }
            } else {
                // Normal mode: start playing immediately
                playerService?.openVideo(video, startTime: startTime)
                rcLog("LOADVIDEO", "Loaded and started playing: \(video.title)", details: "startTime=\(startTime ?? 0)")
            }
        } catch {
            rcLog("LOADVIDEO", "Failed to load video \(videoID): \(error.localizedDescription)", isError: true)
        }
    }

    private func handleLoadMediaSourceVideo(videoID: String, path: String, source: MediaSource, startTime: TimeInterval? = nil, awaitPlayCommand: Bool = false, senderDeviceID: String? = nil) async {
        // Construct full URL from source base URL + path
        let url = source.url.appendingPathComponent(path)

        // Extract filename for title
        let title = url.deletingPathExtension().lastPathComponent

        rcLog("LOADVIDEO", "Loading WebDAV video: \(title)", details: "source=\(source.name), path=\(path), startTime=\(startTime ?? 0), awaitPlay=\(awaitPlayCommand)")

        // Create Video with correct ContentSource
        let video = Video(
            id: VideoID(
                source: .extracted(extractor: MediaFile.webdavProvider, originalURL: url),
                videoID: videoID
            ),
            title: title,
            description: nil,
            author: Author(id: source.id.uuidString, name: source.name),
            duration: 0,
            publishedAt: nil,
            publishedText: nil,
            viewCount: nil,
            likeCount: nil,
            thumbnails: [],
            isLive: false,
            isUpcoming: false,
            scheduledStartTime: nil
        )

        if awaitPlayCommand {
            // Handshake protocol: load video, then pause and notify sender we're ready
            rcLog("LOADVIDEO", "Handshake mode: loading WebDAV video, will pause when ready")
            playerService?.openVideo(video, startTime: startTime)

            // Wait for video to start playing, then pause
            try? await Task.sleep(for: .milliseconds(1000))

            // Pause playback - video is loaded and at correct position but not playing
            playerService?.pause()
            rcLog("LOADVIDEO", "WebDAV video loaded and paused, ready for handoff")

            // Send state update to let sender know we're ready (isPlaying will be false)
            let state = currentRemoteState()
            rcLog("LOADVIDEO", "Sending ready state to sender", details: "videoID=\(state.videoID ?? "nil"), playing=\(state.isPlaying)")
            if let senderID = senderDeviceID {
                try? await networkService.send(command: .stateUpdate(state), to: senderID)
            } else {
                await networkService.broadcast(command: .stateUpdate(state))
            }
        } else {
            // Normal mode: start playing immediately
            playerService?.openVideo(video, startTime: startTime)
            rcLog("LOADVIDEO", "WebDAV video opened: \(title)", details: "startTime=\(startTime ?? 0)")
        }
    }

    private func expandPlayerIfNeeded() {
        #if os(iOS) || os(macOS)
        let isPiPActive = (playerService?.currentBackend as? MPVBackend)?.isPiPActive ?? false
        rcDebug("PLAYER", "expandPlayerIfNeeded - isPiPActive=\(isPiPActive)")
        if !isPiPActive {
            navigationCoordinator?.expandPlayer()
        }
        #else
        navigationCoordinator?.expandPlayer()
        #endif
    }

    // MARK: - State Broadcasting

    private func startStateBroadcast() {
        stateBroadcastTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))

                guard let self, !Task.isCancelled else { break }

                // Don't broadcast state in incognito mode - device should be invisible
                let isIncognito = self.settingsManager?.incognitoModeEnabled ?? false
                guard !isIncognito else { continue }

                let state = self.currentRemoteState()

                // Only broadcast if state actually changed
                if state != self.lastBroadcastState {
                    self.lastBroadcastState = state
                    self.updatePlayerState()
                    await self.networkService.broadcast(command: .stateUpdate(state))
                }

                // Re-request state from connected devices that still show UUID as name
                // (their initial probe response may have been lost)
                await self.requestStateFromUnnamedDevices()
            }
        }
    }

    /// Request state from connected devices that still have UUID as their display name.
    private func requestStateFromUnnamedDevices() async {
        for device in discoveredDevices {
            // Check if name is still the UUID (probe response may have been lost)
            let looksLikeUUID = device.name.count > 30 && device.name.contains("-")
            let isConnected = networkService.connectedPeers.contains(device.id)
            if looksLikeUUID && isConnected {
                rcDebug("BROADCAST", "Re-requesting state from unnamed device: \(device.id.prefix(8))...")
                do {
                    try await networkService.send(command: .requestState, to: device.id)
                } catch {
                    // Connection might be dead, ignore
                }
            }
        }
    }
}
