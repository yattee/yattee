//
//  RemoteControlProtocol.swift
//  Yattee
//
//  Protocol and data types for remote control between Yattee instances.
//

import Foundation

// MARK: - Device Platform

/// Platform type for identifying device capabilities.
enum DevicePlatform: String, Codable, Sendable {
    case iOS
    case macOS
    case tvOS

    /// Returns the platform of the current device.
    static var current: DevicePlatform {
        #if os(iOS)
        return .iOS
        #elseif os(macOS)
        return .macOS
        #elseif os(tvOS)
        return .tvOS
        #else
        return .iOS
        #endif
    }

    /// SF Symbol name for the platform icon.
    var iconName: String {
        switch self {
        case .iOS:
            return "iphone"
        case .macOS:
            return "laptopcomputer"
        case .tvOS:
            return "appletv"
        }
    }
}

// MARK: - Remote Control Commands

/// Commands that can be sent between devices.
enum RemoteControlCommand: Codable, Sendable {
    case play
    case pause
    case togglePlayPause
    case seek(time: TimeInterval)
    case setVolume(Float)
    case setMuted(Bool)
    case setRate(Float)
    case loadVideo(videoID: String, instanceURL: String?, startTime: TimeInterval?, awaitPlayCommand: Bool?)
    case closeVideo
    case toggleFullscreen
    case playNext
    case playPrevious
    case requestState
    case stateUpdate(RemotePlayerState)
}

// MARK: - Remote Player State

/// Snapshot of player state for sharing with remote devices.
struct RemotePlayerState: Codable, Sendable, Equatable {
    let videoID: String?
    let videoTitle: String?
    let channelName: String?
    let thumbnailURL: URL?
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let rate: Float
    let volume: Float
    let isMuted: Bool
    /// Volume mode of the device (mpv = in-app control, system = device volume).
    /// When system mode, remote devices should hide volume controls.
    let volumeMode: String?

    /// Whether the device is currently in fullscreen (landscape) mode.
    let isFullscreen: Bool

    /// Whether fullscreen toggle is available (same logic as player controls fullscreen button).
    let canToggleFullscreen: Bool

    /// Whether there's a previous video in history.
    let hasPrevious: Bool

    /// Whether there's a next video in queue.
    let hasNext: Bool

    /// Creates an empty/idle state.
    static let idle = RemotePlayerState(
        videoID: nil,
        videoTitle: nil,
        channelName: nil,
        thumbnailURL: nil,
        currentTime: 0,
        duration: 0,
        isPlaying: false,
        rate: 1.0,
        volume: 1.0,
        isMuted: false,
        volumeMode: "mpv",
        isFullscreen: false,
        canToggleFullscreen: false,
        hasPrevious: false,
        hasNext: false
    )

    /// Whether this device accepts in-app volume control.
    var acceptsVolumeControl: Bool {
        volumeMode == nil || volumeMode == "mpv"
    }
}

// MARK: - Discovered Device

/// A Yattee instance discovered on the local network.
struct DiscoveredDevice: Identifiable, Codable, Sendable, Equatable, Hashable {
    /// Unique identifier for this device instance.
    let id: String

    /// User-visible device name (e.g., "Arek's MacBook Pro").
    let name: String

    /// Platform type (iOS, macOS, tvOS).
    let platform: DevicePlatform

    /// Title of currently playing video, if any.
    let currentVideoTitle: String?

    /// Channel name of currently playing video, if any.
    let currentChannelName: String?

    /// Thumbnail URL of currently playing video, if any.
    let currentVideoThumbnailURL: URL?

    /// Whether video is currently playing.
    let isPlaying: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Remote Control Message

/// A message sent between devices.
struct RemoteControlMessage: Codable, Sendable {
    /// Unique message identifier for deduplication.
    let id: UUID

    /// Device ID of the sender.
    let senderDeviceID: String

    /// Device name of the sender (for display when TXT record not available).
    let senderDeviceName: String?

    /// Platform of the sender.
    let senderPlatform: DevicePlatform?

    /// Device ID of the target (nil for broadcast).
    let targetDeviceID: String?

    /// The command being sent.
    let command: RemoteControlCommand

    /// When the message was created.
    let timestamp: Date

    init(
        id: UUID = UUID(),
        senderDeviceID: String,
        senderDeviceName: String? = nil,
        senderPlatform: DevicePlatform? = nil,
        targetDeviceID: String? = nil,
        command: RemoteControlCommand,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.senderDeviceID = senderDeviceID
        self.senderDeviceName = senderDeviceName
        self.senderPlatform = senderPlatform
        self.targetDeviceID = targetDeviceID
        self.command = command
        self.timestamp = timestamp
    }
}

// MARK: - Device Info for Advertisement

/// Information advertised via Bonjour TXT record.
struct DeviceAdvertisement: Codable, Sendable {
    let deviceID: String
    let deviceName: String
    let platform: DevicePlatform
    let currentVideoTitle: String?
    let currentChannelName: String?
    let currentVideoThumbnailURL: URL?
    let isPlaying: Bool

    /// Encodes to a TXT record dictionary for Bonjour.
    func toTXTRecord() -> [String: String] {
        var record: [String: String] = [
            "id": deviceID,
            "name": deviceName,
            "platform": platform.rawValue,
            "playing": isPlaying ? "1" : "0"
        ]
        if let title = currentVideoTitle {
            record["title"] = title
        }
        if let channel = currentChannelName {
            record["channel"] = channel
        }
        if let url = currentVideoThumbnailURL {
            record["thumb"] = url.absoluteString
        }
        return record
    }

    /// Creates from a TXT record dictionary.
    static func from(txtRecord: [String: String]) -> DeviceAdvertisement? {
        guard let deviceID = txtRecord["id"],
              let deviceName = txtRecord["name"],
              let platformRaw = txtRecord["platform"],
              let platform = DevicePlatform(rawValue: platformRaw) else {
            return nil
        }

        return DeviceAdvertisement(
            deviceID: deviceID,
            deviceName: deviceName,
            platform: platform,
            currentVideoTitle: txtRecord["title"],
            currentChannelName: txtRecord["channel"],
            currentVideoThumbnailURL: txtRecord["thumb"].flatMap { URL(string: $0) },
            isPlaying: txtRecord["playing"] == "1"
        )
    }

    /// Converts to a DiscoveredDevice.
    func toDiscoveredDevice() -> DiscoveredDevice {
        DiscoveredDevice(
            id: deviceID,
            name: deviceName,
            platform: platform,
            currentVideoTitle: currentVideoTitle,
            currentChannelName: currentChannelName,
            currentVideoThumbnailURL: currentVideoThumbnailURL,
            isPlaying: isPlaying
        )
    }
}
