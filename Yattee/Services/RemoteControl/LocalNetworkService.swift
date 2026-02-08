//
//  LocalNetworkService.swift
//  Yattee
//
//  Handles local network discovery and communication for remote control.
//  Uses Bonjour/mDNS for discovery and TCP for message exchange.
//

import Foundation
import Network
#if os(iOS)
import UIKit
#endif

/// Error thrown when a connection attempt times out.
struct ConnectionTimeoutError: Error, LocalizedError {
    var errorDescription: String? { "Connection timed out" }
}

/// Service for discovering and communicating with other Yattee instances on the local network.
@MainActor
@Observable
final class LocalNetworkService {

    // MARK: - Public State

    /// Discovered devices on the local network.
    private(set) var discoveredDevices: [DiscoveredDevice] = []

    /// Whether the service is actively discovering other devices.
    private(set) var isDiscovering: Bool = false

    /// Whether the service is hosting (accepting connections).
    private(set) var isHosting: Bool = false

    /// Connected peer device IDs.
    private(set) var connectedPeers: Set<String> = []

    // MARK: - Configuration

    /// Bonjour service type for Yattee remote control.
    static let serviceType = "_yattee._tcp"

    /// This device's unique identifier.
    let deviceID: String

    /// This device's display name.
    var deviceName: String

    /// Current advertisement info (updated when player state changes).
    var currentAdvertisement: DeviceAdvertisement {
        DeviceAdvertisement(
            deviceID: deviceID,
            deviceName: deviceName,
            platform: .current,
            currentVideoTitle: _currentVideoTitle,
            currentChannelName: _currentChannelName,
            currentVideoThumbnailURL: _currentVideoThumbnailURL,
            isPlaying: _isPlaying
        )
    }

    // MARK: - Private State

    private var _currentVideoTitle: String?
    private var _currentChannelName: String?
    private var _currentVideoThumbnailURL: URL?
    private var _isPlaying: Bool = false

    private var browser: NWBrowser?
    private var listener: NWListener?
    private var currentListenerID: UUID?  // Track listener instance to ignore stale callbacks
    private var listenerStartTime: Date?  // Track when listener was started for timing diagnostics
    private var connections: [String: NWConnection] = [:]  // Outgoing connections (we initiated)
    private var incomingConnections: [String: NWConnection] = [:]  // Incoming connections (by sender device ID)
    private var pendingConnections: [NWConnection] = []  // Incoming connections not yet identified

    private let queue = DispatchQueue(label: "stream.yattee.remotecontrol")

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

    /// Continuation for incoming commands stream.
    private var commandsContinuation: AsyncStream<RemoteControlMessage>.Continuation?

    /// Stream of incoming remote control commands.
    private(set) var incomingCommands: AsyncStream<RemoteControlMessage>!

    /// Task for periodic status summary logging.
    private var statusSummaryTask: Task<Void, Never>?

    // MARK: - System Device Name

    /// Returns the system device name (used as placeholder/default when no custom name is set).
    static var systemDeviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #elseif os(iOS)
        return UIDevice.current.name
        #elseif os(tvOS)
        return "Apple TV"
        #else
        return "Yattee Device"
        #endif
    }

    // MARK: - Initialization

    init() {
        // Use a persistent device ID stored in UserDefaults
        if let storedID = UserDefaults.standard.string(forKey: "RemoteControl.DeviceID") {
            self.deviceID = storedID
        } else {
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: "RemoteControl.DeviceID")
            self.deviceID = newID
        }

        // Get device name - check for custom name first, then fall back to system name
        let customName = UserDefaults.standard.string(forKey: SettingsKey.remoteControlCustomDeviceName.rawValue) ?? ""
        if !customName.isEmpty {
            self.deviceName = customName
        } else {
            self.deviceName = Self.systemDeviceName
        }

        // Set up the incoming commands stream
        setupCommandsStream()
    }

    // Note: cleanup is handled when stopDiscovery() and stopHosting() are called

    // MARK: - Commands Stream

    private func setupCommandsStream() {
        incomingCommands = AsyncStream { [weak self] continuation in
            self?.commandsContinuation = continuation
        }
    }

    /// Reset the commands stream for a fresh consumer.
    /// Call this when restarting services to ensure the new command listener Task
    /// gets a fresh stream that will properly deliver messages.
    func resetCommandsStream() {
        // Finish the old continuation if any (signals end of old stream)
        commandsContinuation?.finish()
        commandsContinuation = nil
        // Create a fresh stream
        setupCommandsStream()
        rcLog("LIFECYCLE", "Commands stream reset for new consumer")
    }

    /// Update the device name from settings.
    /// Call this when the custom device name setting changes.
    func updateDeviceName() {
        let customName = UserDefaults.standard.string(forKey: SettingsKey.remoteControlCustomDeviceName.rawValue) ?? ""
        if !customName.isEmpty {
            deviceName = customName
        } else {
            deviceName = Self.systemDeviceName
        }
        rcLog("LIFECYCLE", "Device name updated to: \(deviceName)")
    }

    // MARK: - Discovery

    /// Devices that have disappeared from Bonjour but still have active connections.
    /// We'll probe these to check if they're still alive.
    private var devicesToProbe: Set<String> = []

    /// Devices that explicitly disappeared from Bonjour (REMOVED event).
    /// Used to treat health check timeouts as "dead" for these devices, since Bonjour removal is authoritative.
    private var bonjourDisappearedDevices: Set<String> = []

    /// Start discovering other Yattee devices on the local network.
    func startDiscovery() {
        guard !isDiscovering else {
            rcLog("DISCOVERY", "Already discovering, ignoring duplicate start")
            return
        }

        rcLog("DISCOVERY", "Starting device discovery", details: "serviceType=\(Self.serviceType), ownDeviceID=\(self.deviceID)")
        rcLog("DISCOVERY", "Current state: \(discoveredDevices.count) cached devices, \(connectedPeers.count) connected peers")

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: nil),
            using: parameters
        )

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleBrowserStateChange(state)
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor [weak self] in
                self?.handleBrowseResultsChanged(results: results, changes: changes)
            }
        }

        browser.start(queue: queue)
        self.browser = browser
        isDiscovering = true
    }

    /// Stop discovering devices.
    func stopDiscovery() {
        guard isDiscovering else {
            rcDebug("DISCOVERY", "Not discovering, ignoring stop")
            return
        }

        rcLog("DISCOVERY", "Stopping device discovery", details: "Had \(discoveredDevices.count) devices, \(probedDevices.count) probed")
        browser?.cancel()
        browser = nil
        isDiscovering = false
        discoveredDevices.removeAll()
        probedDevices.removeAll()
        rcLog("DISCOVERY", "Discovery stopped and cleared")
    }

    /// Refresh Bonjour advertisement and discovery after returning from background.
    /// This restarts the NWListener and NWBrowser without closing existing connections.
    /// Note: Always unconditionally restarts both services since the caller (coordinator)
    /// decides to call this method only when both should be enabled. The current
    /// isHosting/isDiscovering state may be stale (e.g., after DefunctConnection errors).
    func refreshServices() {
        rcLog("LIFECYCLE", "Refreshing services after foreground transition")
        rcLog("LIFECYCLE", "Pre-refresh state: discovering=\(isDiscovering), hosting=\(isHosting), devices=\(discoveredDevices.count), connections=\(connections.count)/\(incomingConnections.count)")

        // Always restart browser (discovery) - state may be stale after background transition
        rcLog("LIFECYCLE", "Restarting browser")
        browser?.cancel()
        browser = nil
        isDiscovering = false
        // Don't clear discoveredDevices - preserve them during refresh
        // Clear probedDevices to allow re-probing all devices after background transition
        probedDevices.removeAll()
        startDiscovery()

        // Always restart listener (hosting) - state may be stale after DefunctConnection errors
        rcLog("LIFECYCLE", "Restarting listener")
        // Just recreate the listener service to re-advertise
        // Keep existing connections intact
        listener?.cancel()
        listener = nil
        isHosting = false
        startHosting()

        rcLog("LIFECYCLE", "Refresh complete")
    }

    /// Refresh only Bonjour discovery after returning from background.
    /// Use when hosting is intentionally disabled (non-discoverable or incognito mode).
    /// Also ensures hosting is stopped in case it was running before background transition.
    func refreshDiscoveryOnly() {
        rcLog("LIFECYCLE", "Refreshing discovery only (hosting disabled)")
        rcLog("LIFECYCLE", "Pre-refresh state: discovering=\(isDiscovering), hosting=\(isHosting), devices=\(discoveredDevices.count), connections=\(connections.count)")

        // Ensure hosting is stopped - it may have been running before conditions changed
        // (e.g., incognito mode enabled while in background)
        if isHosting {
            rcLog("LIFECYCLE", "Stopping hosting as part of discovery-only refresh")
            stopHosting()
        }

        // Always restart browser - state may be stale after background transition
        rcLog("LIFECYCLE", "Restarting browser")
        browser?.cancel()
        browser = nil
        isDiscovering = false
        // Don't clear discoveredDevices - preserve them during refresh
        // Clear probedDevices to allow re-probing all devices after background transition
        probedDevices.removeAll()
        startDiscovery()

        rcLog("LIFECYCLE", "Discovery refresh complete")
    }

    private func handleBrowserStateChange(_ state: NWBrowser.State) {
        switch state {
        case .setup:
            rcDebug("BROWSER", "State: setup")
        case .ready:
            rcLog("BROWSER", "State: ready - actively looking for \(Self.serviceType) services")
        case .failed(let error):
            rcLog("BROWSER", "State: FAILED - \(error.localizedDescription)", isError: true)
            isDiscovering = false
        case .cancelled:
            rcLog("BROWSER", "State: cancelled")
            isDiscovering = false
        case .waiting(let error):
            rcLog("BROWSER", "State: waiting - \(error.localizedDescription)", isWarning: true)
        @unknown default:
            rcLog("BROWSER", "State: unknown", isWarning: true)
        }
    }

    private func handleBrowseResultsChanged(results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        // Log the changes for debugging
        var changeDescriptions: [String] = []
        for change in changes {
            switch change {
            case .added(let result):
                if case let .service(name, _, _, _) = result.endpoint {
                    changeDescriptions.append("ADDED:\(name)")
                }
            case .removed(let result):
                if case let .service(name, _, _, _) = result.endpoint {
                    changeDescriptions.append("REMOVED:\(name)")
                }
            case .changed(old: _, new: let newResult, flags: let flags):
                if case let .service(name, _, _, _) = newResult.endpoint {
                    changeDescriptions.append("CHANGED:\(name) flags=\(flags)")
                }
            case .identical:
                break
            @unknown default:
                changeDescriptions.append("UNKNOWN")
            }
        }

        rcLog("BROWSE", "Results changed: \(results.count) total, changes: [\(changeDescriptions.joined(separator: ", "))]")

        // Track which devices are currently visible
        var currentDeviceIDs: Set<String> = []
        var newDevices: [DiscoveredDevice] = []

        for result in results {
            // Extract service name from endpoint
            var serviceName: String?
            var serviceType: String?
            var domain: String?

            if case let .service(name, type, dom, _) = result.endpoint {
                serviceName = name
                serviceType = type
                domain = dom

                // Skip our own service (including Bonjour conflict suffixes like "(2)")
                // When rapidly toggling remote control, Bonjour may not fully de-register
                // the old service before the new one starts, causing conflict naming
                if name == deviceID || (name.hasPrefix(deviceID) && name.contains("(")) {
                    rcDebug("BROWSE", "Skipping own service: \(name)")
                    continue
                }

                currentDeviceIDs.insert(name)
                // Device is back in Bonjour results - clear the disappeared flag
                bonjourDisappearedDevices.remove(name)
            }

            // Extract TXT record data - try to get it from metadata
            let metadata = result.metadata
            var txtDict: [String: String]?
            var txtDetails: String = "none"

            switch metadata {
            case .bonjour(let txtRecord):
                txtDict = parseTXTRecord(txtRecord)
                if let dict = txtDict {
                    txtDetails = dict.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                }
            case .none:
                txtDetails = "no metadata yet"
            @unknown default:
                txtDetails = "unknown metadata type"
            }

            if let name = serviceName {
                rcLog("BROWSE", "Service: \(name)", details: "type=\(serviceType ?? "?"), domain=\(domain ?? "?"), TXT=[\(txtDetails)]")
            }

            if let txtDict, let advertisement = DeviceAdvertisement.from(txtRecord: txtDict) {
                // Skip if it's our own device
                if advertisement.deviceID != deviceID {
                    let device = advertisement.toDiscoveredDevice()
                    newDevices.append(device)
                    // Cache the device info for when it reappears
                    deviceInfoCache[device.id] = (name: device.name, platform: device.platform)
                    // Track first-seen time for unresponsive device cleanup
                    if deviceFirstSeen[device.id] == nil {
                        deviceFirstSeen[device.id] = Date()
                    }
                    rcLog("BROWSE", "Added device from TXT: \(advertisement.deviceName) (\(advertisement.platform))")
                    // Probe to establish outgoing connection even if we have TXT info
                    // This ensures bidirectional connectivity (both outgoing and incoming connections)
                    probeDeviceForInfo(device)
                } else {
                    rcDebug("BROWSE", "Skipping own device from TXT: \(advertisement.deviceID)")
                }
            } else if let serviceName {
                // No TXT record yet - check cache, existing list, or create basic entry
                // Track first-seen time for unresponsive device cleanup
                if deviceFirstSeen[serviceName] == nil {
                    deviceFirstSeen[serviceName] = Date()
                }

                if let cachedInfo = deviceInfoCache[serviceName] {
                    // Use cached info (from previous discovery or message exchange)
                    rcLog("BROWSE", "Using cached info for \(serviceName): \(cachedInfo.name) (\(cachedInfo.platform))")
                    let existingDevice = discoveredDevices.first(where: { $0.id == serviceName })
                    let device = DiscoveredDevice(
                        id: serviceName,
                        name: cachedInfo.name,
                        platform: cachedInfo.platform,
                        currentVideoTitle: existingDevice?.currentVideoTitle,
                        currentChannelName: existingDevice?.currentChannelName,
                        currentVideoThumbnailURL: existingDevice?.currentVideoThumbnailURL,
                        isPlaying: existingDevice?.isPlaying ?? false
                    )
                    newDevices.append(device)
                    // Probe to establish outgoing connection for bidirectional communication
                    probeDeviceForInfo(device)
                } else if let existingDevice = discoveredDevices.first(where: { $0.id == serviceName }) {
                    // Preserve existing device info (name, platform, etc. from previous messages)
                    rcDebug("BROWSE", "Preserving existing info for \(serviceName): \(existingDevice.name)")
                    newDevices.append(existingDevice)
                    // Probe to establish outgoing connection for bidirectional communication
                    probeDeviceForInfo(existingDevice)
                } else {
                    // No TXT record and no cache - add with placeholder name and probe for real info
                    // This ensures device appears in UI even if probe fails (mDNS issues, etc.)
                    rcLog("BROWSE", "No TXT/cache for \(serviceName), adding placeholder and probing", isWarning: true)

                    let device = DiscoveredDevice(
                        id: serviceName,
                        name: String(localized: "remoteControl.device.placeholder"),
                        platform: .iOS,  // Default, will be updated when we get a response
                        currentVideoTitle: nil,
                        currentChannelName: nil,
                        currentVideoThumbnailURL: nil,
                        isPlaying: false
                    )

                    // Add to discovered devices so user can see and tap on it
                    newDevices.append(device)

                    // Auto-probe this device to get its real info - once we get a response,
                    // the device will be updated with proper name via updateDiscoveredDeviceInfo
                    probeDeviceForInfo(device)
                }
            } else {
                rcLog("BROWSE", "Service without name or TXT record", isWarning: true)
            }
        }

        // Find devices that disappeared from Bonjour (went to background, etc.)
        let previousDeviceIDs = Set(discoveredDevices.map { $0.id })
        let disappearedDeviceIDs = previousDeviceIDs.subtracting(currentDeviceIDs)
        for deviceID in disappearedDeviceIDs {
            // Remove from probedDevices so it can be re-probed when it comes back
            probedDevices.remove(deviceID)
            // Mark as explicitly disappeared from Bonjour (authoritative signal)
            bonjourDisappearedDevices.insert(deviceID)
            let deviceName = deviceInfoCache[deviceID]?.name ?? deviceID
            rcLog("BROWSE", "Device disappeared: \(deviceName) (\(deviceID))", isWarning: true)

            // If this device has an active connection, probe it to check if still alive
            if connectedPeers.contains(deviceID) {
                devicesToProbe.insert(deviceID)
                rcLog("BROWSE", "Disappeared device \(deviceName) has active connection - probing health", isWarning: true)
                // Trigger async probe
                Task {
                    await self.probeConnectionHealth(deviceID: deviceID)
                }
            } else {
                rcDebug("BROWSE", "Disappeared device \(deviceName) has no active connection")
            }
        }

        // Preserve devices that have active connections but aren't in browse results
        // (they may have connected before Bonjour detected them, or Bonjour is slow to update)
        var newDeviceIDs = Set(newDevices.map { $0.id })
        for deviceID in connectedPeers {
            if !newDeviceIDs.contains(deviceID), let cachedInfo = deviceInfoCache[deviceID] {
                // Device has active connection but isn't in browse results - preserve it
                let existingDevice = discoveredDevices.first { $0.id == deviceID }
                let device = DiscoveredDevice(
                    id: deviceID,
                    name: cachedInfo.name,
                    platform: cachedInfo.platform,
                    currentVideoTitle: existingDevice?.currentVideoTitle,
                    currentChannelName: existingDevice?.currentChannelName,
                    currentVideoThumbnailURL: existingDevice?.currentVideoThumbnailURL,
                    isPlaying: existingDevice?.isPlaying ?? false
                )
                newDevices.append(device)
                newDeviceIDs.insert(deviceID)
                rcLog("BROWSE", "Preserving connected device not in results: \(cachedInfo.name)")
            }
        }

        // Also preserve devices we've recently communicated with (within timeout)
        // This handles the case where a device's connection was cleaned up but we still
        // know it exists (e.g., iPhone went to background briefly)
        let now = Date()
        var expiredDevices: [String] = []
        for (deviceID, lastSeen) in recentlySeenDevices {
            let timeSinceLastSeen = now.timeIntervalSince(lastSeen)
            if timeSinceLastSeen > recentlySeenTimeout {
                expiredDevices.append(deviceID)
                let deviceName = deviceInfoCache[deviceID]?.name ?? deviceID
                rcLog("BROWSE", "Device \(deviceName) expired from recently-seen (\(Int(timeSinceLastSeen))s > \(Int(self.recentlySeenTimeout))s)")
            } else if !newDeviceIDs.contains(deviceID), let cachedInfo = deviceInfoCache[deviceID] {
                // Device was recently seen but not in browse results or connected - preserve it
                let existingDevice = discoveredDevices.first { $0.id == deviceID }
                let device = DiscoveredDevice(
                    id: deviceID,
                    name: cachedInfo.name,
                    platform: cachedInfo.platform,
                    currentVideoTitle: existingDevice?.currentVideoTitle,
                    currentChannelName: existingDevice?.currentChannelName,
                    currentVideoThumbnailURL: existingDevice?.currentVideoThumbnailURL,
                    isPlaying: existingDevice?.isPlaying ?? false
                )
                newDevices.append(device)
                newDeviceIDs.insert(deviceID)
                rcLog("BROWSE", "Preserving recently-seen device: \(cachedInfo.name) (last seen \(Int(timeSinceLastSeen))s ago)")
            }
        }
        // Clean up expired entries
        for deviceID in expiredDevices {
            recentlySeenDevices.removeValue(forKey: deviceID)
            // Allow re-probing expired devices so they can reconnect
            probedDevices.remove(deviceID)
        }

        discoveredDevices = newDevices

        // Log summary of discovered devices
        let deviceSummary = newDevices.map { "\($0.name) (\($0.platform))" }.joined(separator: ", ")
        rcLog("BROWSE", "Discovery complete: \(newDevices.count) devices", details: deviceSummary.isEmpty ? "none" : deviceSummary)
    }

    /// Devices we've already tried to probe (to avoid repeated connection attempts).
    private var probedDevices: Set<String> = []

    /// Cache of device info (name, platform) that persists across browse result changes.
    /// This helps restore device info when a device goes to background and comes back.
    private var deviceInfoCache: [String: (name: String, platform: DevicePlatform)] = [:]

    /// Devices that have recently communicated with us (within last 30 seconds).
    /// Used to preserve devices in the list even if Bonjour doesn't see them.
    private(set) var recentlySeenDevices: [String: Date] = [:]
    private let recentlySeenTimeout: TimeInterval = 30

    /// When we first discovered each device (for removing stale Bonjour entries).
    private var deviceFirstSeen: [String: Date] = [:]
    /// Timeout for devices we haven't been able to communicate with.
    private let unresponsiveTimeout: TimeInterval = 60

    /// Status of a discovered device's connection.
    enum DeviceStatus {
        case connected          // Active connection
        case recentlySeen(ago: TimeInterval)  // No connection but seen recently
        case discoveredOnly     // Only via Bonjour, no communication yet
    }

    /// Get the status of a device.
    func deviceStatus(for deviceID: String) -> DeviceStatus {
        if connectedPeers.contains(deviceID) {
            return .connected
        } else if let lastSeen = recentlySeenDevices[deviceID] {
            let ago = Date().timeIntervalSince(lastSeen)
            if ago <= recentlySeenTimeout {
                return .recentlySeen(ago: ago)
            }
        }
        return .discoveredOnly
    }

    /// Clean up devices that have exceeded the recently-seen timeout.
    /// Call this periodically to remove stale devices from the list.
    func cleanupStaleDevices() {
        let now = Date()
        var devicesToRemove: [String] = []

        // Find expired devices in recentlySeenDevices (were communicating but stopped)
        for (deviceID, lastSeen) in recentlySeenDevices {
            let timeSinceLastSeen = now.timeIntervalSince(lastSeen)
            if timeSinceLastSeen > recentlySeenTimeout {
                devicesToRemove.append(deviceID)
                recentlySeenDevices.removeValue(forKey: deviceID)
                let deviceName = deviceInfoCache[deviceID]?.name ?? deviceID
                rcLog("CLEANUP", "[\(deviceName)] Expired from recentlySeenDevices (\(Int(timeSinceLastSeen))s > \(Int(recentlySeenTimeout))s)")
            }
        }

        // Find unresponsive devices (discovered but never successfully communicated)
        for (deviceID, firstSeen) in deviceFirstSeen {
            let timeSinceFirstSeen = now.timeIntervalSince(firstSeen)
            if timeSinceFirstSeen > unresponsiveTimeout {
                if !devicesToRemove.contains(deviceID) {
                    devicesToRemove.append(deviceID)
                }
                deviceFirstSeen.removeValue(forKey: deviceID)
                let deviceName = deviceInfoCache[deviceID]?.name ?? deviceID
                rcLog("CLEANUP", "[\(deviceName)] Never responded after \(Int(timeSinceFirstSeen))s", isWarning: true)
            }
        }

        // Remove stale devices from the list
        for deviceID in devicesToRemove {
            if !connectedPeers.contains(deviceID) {
                if let index = discoveredDevices.firstIndex(where: { $0.id == deviceID }) {
                    let device = discoveredDevices[index]
                    discoveredDevices.remove(at: index)
                    // Clear from probed set so we'll try again if it comes back
                    probedDevices.remove(deviceID)
                    rcLog("CLEANUP", "[\(device.name)] Removed stale device from list")
                }
            }
        }
    }

    /// Probe a connection to check if it's still alive.
    /// If the connection is dead, clean it up and transition the device to "recently seen" status.
    private func probeConnectionHealth(deviceID: String) async {
        guard devicesToProbe.contains(deviceID) else { return }
        devicesToProbe.remove(deviceID)

        let deviceName = deviceInfoCache[deviceID]?.name ?? deviceID
        rcLog("HEALTH", "[\(deviceName)] Probing connection health")

        // Check if we have an active connection (outgoing or incoming)
        let outgoingConnection = connections[deviceID]
        let incomingConnection = incomingConnections[deviceID]

        let outgoingState = outgoingConnection.map { String(describing: $0.state) } ?? "nil"
        let incomingState = incomingConnection.map { String(describing: $0.state) } ?? "nil"
        rcLog("HEALTH", "[\(deviceName)] Connection states: outgoing=\(outgoingState), incoming=\(incomingState)")

        // Check outgoing connection state
        if let connection = outgoingConnection {
            await probeConnection(connection, deviceID: deviceID, isOutgoing: true)
            return
        }

        // Check incoming connection state
        if let connection = incomingConnection {
            await probeConnection(connection, deviceID: deviceID, isOutgoing: false)
            return
        }

        // No active connection found - device should already be cleaned up
        rcLog("HEALTH", "[\(deviceName)] No active connection found - removing from connectedPeers", isWarning: true)
        connectedPeers.remove(deviceID)
    }

    /// Probe a specific connection to check if it's still alive.
    private func probeConnection(_ connection: NWConnection, deviceID: String, isOutgoing: Bool) async {
        let deviceName = deviceInfoCache[deviceID]?.name ?? deviceID
        let connectionType = isOutgoing ? "outgoing" : "incoming"
        let state = connection.state
        rcLog("HEALTH", "[\(deviceName)] Probing \(connectionType) connection (state=\(state))")

        switch state {
        case .ready:
            // Try sending a ping (requestState) and wait for response or connection death
            rcLog("HEALTH", "[\(deviceName)] Connection ready - sending ping...")
            let isAlive = await sendHealthCheckAndWaitForResponse(to: deviceID, using: connection)
            if isAlive {
                rcLog("HEALTH", "[\(deviceName)] Health check PASSED - connection alive")
                recentlySeenDevices[deviceID] = Date()
            } else {
                rcLog("HEALTH", "[\(deviceName)] Health check FAILED - connection dead", isWarning: true)
                cleanupDeadConnection(deviceID: deviceID)
            }

        case .failed, .cancelled:
            rcLog("HEALTH", "[\(deviceName)] \(connectionType) connection already dead (state=\(state))", isWarning: true)
            cleanupDeadConnection(deviceID: deviceID)

        default:
            // Connection in transitional state, wait a bit and check again
            rcLog("HEALTH", "[\(deviceName)] \(connectionType) in transitional state (\(state)) - scheduling recheck")
            Task {
                try? await Task.sleep(for: .seconds(2))
                devicesToProbe.insert(deviceID)
                await probeConnectionHealth(deviceID: deviceID)
            }
        }
    }

    /// Send a health check and wait for a response or connection death.
    /// Returns true if connection is alive, false if dead.
    ///
    /// IMPORTANT: This does NOT do its own receive() call. Doing so would race with the
    /// regular receiveMessage() loop and corrupt message framing (the 4-byte length header
    /// could be read by one receive while the body is read by another, causing desync).
    /// Instead, we send a ping and monitor recentlySeenDevices for updates from the
    /// regular receive loop.
    private func sendHealthCheckAndWaitForResponse(to deviceID: String, using connection: NWConnection) async -> Bool {
        let deviceName = deviceInfoCache[deviceID]?.name ?? deviceID
        rcDebug("HEALTH", "[\(deviceName)] Sending requestState ping...")

        let message = RemoteControlMessage(
            senderDeviceID: self.deviceID,
            senderDeviceName: self.deviceName,
            senderPlatform: .current,
            targetDeviceID: deviceID,
            command: .requestState
        )

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(message)

            var length = UInt32(data.count).bigEndian
            var framedData = Data(bytes: &length, count: 4)
            framedData.append(data)

            // Record the time before sending so we can detect new responses
            let sendTime = Date()

            // Send the health check message
            let sendResult: Bool = await withCheckedContinuation { continuation in
                connection.send(content: framedData, completion: .contentProcessed { [weak self] error in
                    Task { @MainActor [weak self] in
                        if let error {
                            self?.rcLog("HEALTH", "[\(deviceName)] Ping send failed: \(error.localizedDescription)", isError: true)
                            continuation.resume(returning: false)
                        } else {
                            self?.rcDebug("HEALTH", "[\(deviceName)] Ping sent, waiting for response...")
                            continuation.resume(returning: true)
                        }
                    }
                })
            }

            guard sendResult else {
                return false
            }

            // Wait for a response by monitoring recentlySeenDevices updates
            // The regular receiveMessage() loop will update this timestamp when it gets the response
            let timeout: TimeInterval = 3.0
            let checkInterval: TimeInterval = 0.1
            var elapsed: TimeInterval = 0

            while elapsed < timeout {
                try? await Task.sleep(for: .milliseconds(Int(checkInterval * 1000)))
                elapsed += checkInterval

                // Check if we received data from this device after we sent the ping
                if let lastSeen = recentlySeenDevices[deviceID], lastSeen > sendTime {
                    rcLog("HEALTH", "[\(deviceName)] Ping response received - ALIVE")
                    return true
                }

                // Check if connection died
                if connection.state != .ready {
                    rcLog("HEALTH", "[\(deviceName)] Connection died (state=\(connection.state)) - DEAD", isWarning: true)
                    return false
                }
            }

            // Timeout without response - check if device explicitly disappeared from Bonjour
            // Bonjour removal is authoritative - if device stopped advertising, it's intentionally offline
            if bonjourDisappearedDevices.contains(deviceID) {
                rcLog("HEALTH", "[\(deviceName)] Ping timed out and device disappeared from Bonjour - DEAD", isWarning: true)
                return false
            }

            // Check current connection state
            if connection.state == .ready {
                // Connection still ready but no response - could be slow, assume alive for now
                rcLog("HEALTH", "[\(deviceName)] Ping timed out but connection ready - assuming alive")
                return true
            } else {
                rcLog("HEALTH", "[\(deviceName)] Ping timed out, connection not ready (state=\(connection.state)) - DEAD", isWarning: true)
                return false
            }

        } catch {
            rcLog("HEALTH", "[\(deviceName)] Ping encoding failed: \(error.localizedDescription)", isError: true)
            return false
        }
    }

    /// Clean up a dead connection and transition device to "recently seen" status.
    private func cleanupDeadConnection(deviceID: String) {
        let deviceName = deviceInfoCache[deviceID]?.name ?? deviceID
        rcLog("HEALTH", "[\(deviceName)] Cleaning up dead connection - transitioning to recently-seen")

        // Cancel and remove connections
        connections[deviceID]?.cancel()
        connections.removeValue(forKey: deviceID)

        incomingConnections[deviceID]?.cancel()
        incomingConnections.removeValue(forKey: deviceID)

        // Remove from connected peers
        connectedPeers.remove(deviceID)

        // Mark as recently seen so it transitions to orange status instead of disappearing
        // Only if we had recent communication with it
        if recentlySeenDevices[deviceID] != nil {
            // Keep existing timestamp - it will naturally expire
            rcLog("HEALTH", "[\(deviceName)] Transitioned to recently-seen (existing timestamp)")
        } else {
            // Set a timestamp so it shows "recently seen" briefly before expiring
            recentlySeenDevices[deviceID] = Date()
            rcLog("HEALTH", "[\(deviceName)] Marked as recently-seen (new timestamp)")
        }

        // Allow re-probing when it comes back
        probedDevices.remove(deviceID)

        // Clear the Bonjour disappeared flag since we've handled the cleanup
        bonjourDisappearedDevices.remove(deviceID)
    }

    /// Probe a device to get its info by connecting and requesting state.
    /// Includes retry logic with exponential backoff for connection failures.
    private func probeDeviceForInfo(_ device: DiscoveredDevice) {
        // Only probe once per device
        guard !probedDevices.contains(device.id) else { return }
        probedDevices.insert(device.id)

        rcLog("PROBE", "[\(device.name)] Probing device to get info (id=\(device.id))")

        Task {
            var retryCount = 0
            let maxRetries = 4  // Retry up to 4 times (5 total attempts)
            
            // Exponential backoff delays: 0.5s, 1s, 2s, 3s
            let retryDelays: [TimeInterval] = [0.5, 1.0, 2.0, 3.0]

            while retryCount <= maxRetries {
                do {
                    rcLog("PROBE", "[\(device.name)] Attempt \(retryCount + 1)/\(maxRetries + 1) - connecting...")
                    try await connect(to: device)
                    // Send a requestState command to get the device's info
                    try await send(command: .requestState, to: device.id)
                    rcLog("PROBE", "[\(device.name)] Probe SUCCEEDED on attempt \(retryCount + 1)")
                    return
                } catch {
                    // Retry on any connection error (timeout, TCP RST, cancellation, etc.)
                    // Remote device's listener may not be ready yet
                    retryCount += 1
                    if retryCount <= maxRetries {
                        let delay = retryDelays[min(retryCount - 1, retryDelays.count - 1)]
                        rcLog("PROBE", "[\(device.name)] Attempt \(retryCount)/\(maxRetries + 1) failed: \(error.localizedDescription), retrying in \(delay)s...", isWarning: true)
                        // Clean up failed connection before retry
                        await MainActor.run {
                            connections.removeValue(forKey: device.id)
                            connectedPeers.remove(device.id)
                        }
                        // Wait with exponential backoff - remote listener may need time to start
                        try? await Task.sleep(for: .seconds(delay))
                    } else {
                        rcLog("PROBE", "[\(device.name)] Probe FAILED after \(maxRetries + 1) attempts: \(error.localizedDescription)", isError: true)
                    }
                }
            }

            // Remove from probed set so we can try again if re-discovered
            _ = await MainActor.run {
                self.probedDevices.remove(device.id)
                self.rcLog("PROBE", "[\(device.name)] Removed from probed set - can retry on re-discovery")
            }
        }
    }

    private func parseTXTRecord(_ record: NWTXTRecord) -> [String: String] {
        // NWTXTRecord.dictionary already returns [String: String]
        let dict = record.dictionary
        rcDebug("BROWSE", "Parsed TXT record: \(dict.count) entries [\(dict.keys.joined(separator: ", "))]")
        return dict
    }

    // MARK: - Hosting

    /// Start hosting to allow other devices to connect.
    func startHosting() {
        guard !isHosting else {
            rcDebug("HOSTING", "Already hosting, ignoring duplicate start")
            return
        }

        rcLog("HOSTING", "Starting hosting", details: "deviceID=\(self.deviceID), name=\(self.deviceName), serviceType=\(Self.serviceType)")

        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true

            let listener = try NWListener(using: parameters)

            // Generate unique ID for this listener to track stale callbacks
            let listenerID = UUID()
            currentListenerID = listenerID

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleListenerStateChange(state, listenerID: listenerID)
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.handleNewConnection(connection)
                }
            }

            // Start listener WITHOUT Bonjour advertisement first
            listener.start(queue: queue)
            self.listener = listener
            self.listenerStartTime = Date()  // Track startup time for diagnostics
            isHosting = true
            startStatusSummaryTimer()
            rcLog("HOSTING", "Listener started, waiting for ready state before advertising...")

            // Defer Bonjour advertisement to give listener time to reach .ready state
            // This prevents race condition where remote devices try to connect before we're ready
            Task { @MainActor [weak self, weak listener] in
                guard let self, let listener else { return }
                
                // Wait 300ms for listener to stabilize
                try? await Task.sleep(for: .milliseconds(300))
                
                // Verify listener is still valid (not cancelled during delay)
                guard self.listener === listener, listenerID == self.currentListenerID else {
                    self.rcLog("HOSTING", "Listener cancelled during startup delay, skipping advertisement", isWarning: true)
                    return
                }
                
                // Now advertise via Bonjour
                let advert = self.currentAdvertisement
                let txtDict = advert.toTXTRecord()
                let txtDetails = txtDict.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                self.rcLog("HOSTING", "Advertising via Bonjour after stabilization", details: "TXT=[\(txtDetails)]")
                let txtRecord = NWTXTRecord(txtDict)
                listener.service = NWListener.Service(
                    name: self.deviceID,
                    type: Self.serviceType,
                    txtRecord: txtRecord
                )
                self.rcLog("HOSTING", "Bonjour advertisement active")
            }

        } catch {
            rcLog("HOSTING", "Failed to start listener: \(error.localizedDescription)", isError: true)
        }
    }

    /// Stop hosting.
    func stopHosting() {
        guard isHosting else {
            rcDebug("HOSTING", "Not hosting, ignoring stop")
            return
        }

        rcLog("HOSTING", "Stopping hosting", details: "incoming=\(incomingConnections.count), pending=\(pendingConnections.count)")
        currentListenerID = nil  // Clear before cancel to ignore the cancelled callback
        listenerStartTime = nil  // Clear timing diagnostic
        listener?.cancel()
        listener = nil
        isHosting = false

        // Close all incoming connections
        for (deviceID, connection) in incomingConnections {
            let deviceName = deviceInfoCache[deviceID]?.name ?? deviceID
            rcLog("HOSTING", "Closing incoming connection: \(deviceName)")
            connection.cancel()
            connectedPeers.remove(deviceID)
        }
        incomingConnections.removeAll()

        // Close all pending connections
        for connection in pendingConnections {
            rcDebug("HOSTING", "Closing pending connection: \(connection.endpoint)")
            connection.cancel()
        }
        pendingConnections.removeAll()
        stopStatusSummaryTimer()
        rcLog("HOSTING", "Hosting stopped")
    }

    // MARK: - Status Summary Timer

    /// Start periodic status summary logging (every 30 seconds).
    private func startStatusSummaryTimer() {
        statusSummaryTask?.cancel()
        statusSummaryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled else { break }
                self.logStatusSummary()
            }
        }
    }

    /// Stop the status summary timer.
    private func stopStatusSummaryTimer() {
        statusSummaryTask?.cancel()
        statusSummaryTask = nil
    }

    /// Log a comprehensive status summary for debugging.
    private func logStatusSummary() {
        // Collect status info
        let hostingStatus = isHosting ? "YES" : "NO"
        let listenerPort = listener?.port?.rawValue.description ?? "N/A"
        let browsingStatus = isDiscovering ? "YES" : "NO"

        // Discovered devices
        let deviceNames = discoveredDevices.map { $0.name }
        let devicesSummary = deviceNames.isEmpty ? "none" : deviceNames.joined(separator: ", ")

        // Connected peers
        let peerNames = connectedPeers.compactMap { deviceInfoCache[$0]?.name ?? $0 }
        let peersSummary = peerNames.isEmpty ? "none" : peerNames.joined(separator: ", ")

        // Connection counts by state
        let outgoingReady = connections.values.filter { $0.state == .ready }.count
        let outgoingOther = connections.count - outgoingReady
        let incomingReady = incomingConnections.values.filter { $0.state == .ready }.count
        let incomingOther = incomingConnections.count - incomingReady

        // Recently seen devices with time ago
        let now = Date()
        let recentlySeenSummary = recentlySeenDevices.map { (deviceID, lastSeen) -> String in
            let name = deviceInfoCache[deviceID]?.name ?? deviceID.prefix(8).description
            let ago = Int(now.timeIntervalSince(lastSeen))
            return "\(name) (\(ago)s ago)"
        }.joined(separator: ", ")

        // Build summary
        var summary = """
            === STATUS SUMMARY ===
              Hosting: \(hostingStatus) on port \(listenerPort)
              Browsing: \(browsingStatus)
              Discovered: \(discoveredDevices.count) [\(devicesSummary)]
              Connected: \(connectedPeers.count) [\(peersSummary)]
              Outgoing: \(outgoingReady) ready, \(outgoingOther) other
              Incoming: \(incomingReady) ready, \(incomingOther) other
            """

        if !recentlySeenDevices.isEmpty {
            summary += "\n  Recently seen: \(recentlySeenSummary)"
        }

        rcLog("STATUS", summary)
    }

    /// Update the advertised state (call when player state changes).
    func updateAdvertisement(videoTitle: String?, channelName: String?, thumbnailURL: URL?, isPlaying: Bool) {
        // Skip if nothing changed (avoid redundant Bonjour TXT record updates)
        guard videoTitle != _currentVideoTitle ||
              channelName != _currentChannelName ||
              thumbnailURL != _currentVideoThumbnailURL ||
              isPlaying != _isPlaying else { return }

        _currentVideoTitle = videoTitle
        _currentChannelName = channelName
        _currentVideoThumbnailURL = thumbnailURL
        _isPlaying = isPlaying

        // Update the TXT record if we're hosting
        if isHosting, let listener = listener {
            let txtRecord = NWTXTRecord(currentAdvertisement.toTXTRecord())
            listener.service = NWListener.Service(
                name: deviceID,
                type: Self.serviceType,
                txtRecord: txtRecord
            )
        }
    }

    private func handleListenerStateChange(_ state: NWListener.State, listenerID: UUID) {
        // Ignore callbacks from old listeners (e.g., during refreshServices())
        guard listenerID == currentListenerID else {
            rcDebug("LISTENER", "Ignoring state \(state) from old listener")
            return
        }

        switch state {
        case .setup:
            rcDebug("LISTENER", "State: setup")
        case .ready:
            // Calculate time to ready for diagnostics
            let timeToReady = listenerStartTime.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
            if let port = listener?.port {
                rcLog("LISTENER", "State: ready on port \(port.rawValue)", details: "advertising as \(self.deviceID), took \(timeToReady)ms to become ready")
            }
        case .failed(let error):
            rcLog("LISTENER", "State: FAILED - \(error.localizedDescription)", isError: true)
            isHosting = false
        case .cancelled:
            rcLog("LISTENER", "State: cancelled")
            isHosting = false
        case .waiting(let error):
            rcLog("LISTENER", "State: waiting - \(error.localizedDescription)", isWarning: true)
        @unknown default:
            rcLog("LISTENER", "State: unknown", isWarning: true)
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        rcLog("CONNECT", "New incoming connection from \(connection.endpoint)")
        pendingConnections.append(connection)
        setupConnectionHandlers(connection, isOutgoing: false)
        connection.start(queue: queue)
    }

    // MARK: - Connection Management

    /// Connect to a discovered device with a timeout.
    func connect(to device: DiscoveredDevice) async throws {
        // Check if we already have a ready incoming connection from this device
        // Incoming connections are more reliable since the remote device initiated them
        if let incomingConnection = incomingConnections[device.id], 
           incomingConnection.state == .ready {
            rcLog("CONNECT", "Using existing incoming connection from \(device.name)")
            // Mark this device as one we're controlling (add to controllingDevices in caller)
            return
        }
        
        // Check if we already have an outgoing connection (ready or establishing)
        if let existingOutgoing = connections[device.id] {
            if existingOutgoing.state == .ready {
                rcDebug("CONNECT", "Already connected to \(device.name) (\(device.id))")
                return
            } else {
                // Connection exists but not ready - let it continue establishing
                rcLog("CONNECT", "Outgoing connection to \(device.name) already in progress (state: \(existingOutgoing.state))")
                return
            }
        }

        rcLog("CONNECT", "No existing connection found, initiating outgoing connection to \(device.name)", details: "id=\(device.id), platform=\(device.platform)")

        // Create endpoint from device ID (service name)
        let endpoint = NWEndpoint.service(
            name: device.id,
            type: Self.serviceType,
            domain: "local.",
            interface: nil
        )

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let connection = NWConnection(to: endpoint, using: parameters)
        connections[device.id] = connection

        setupConnectionHandlers(connection, isOutgoing: true, deviceID: device.id)

        // Wait for connection with 10-second timeout
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    try await self.waitForConnectionReady(connection, device: device)
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(10))
                    throw ConnectionTimeoutError()
                }

                // Wait for first to complete (either connected or timeout)
                _ = try await group.next()
                group.cancelAll()
            }
        } catch is ConnectionTimeoutError {
            // Clean up the connection on timeout
            rcLog("CONNECT", "Connection to \(device.id) timed out after 10 seconds", isWarning: true)
            connection.cancel()
            connections.removeValue(forKey: device.id)
            throw ConnectionTimeoutError()
        } catch {
            // Clean up on other errors
            connections.removeValue(forKey: device.id)
            throw error
        }
    }

    /// Wait for a connection to become ready.
    private func waitForConnectionReady(_ connection: NWConnection, device: DiscoveredDevice) async throws {
        let startTime = Date()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Use a class to track if we've resumed, avoiding concurrent access issues
            final class ResumedState: @unchecked Sendable {
                var resumed = false
            }
            let state = ResumedState()

            connection.stateUpdateHandler = { [weak self] connectionState in
                guard !state.resumed else { return }

                Task { @MainActor [weak self] in
                    let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)

                    switch connectionState {
                    case .setup:
                        self?.rcDebug("CONNECT", "[\(device.name)] State: setup (\(elapsed)ms)")

                    case .preparing:
                        self?.rcDebug("CONNECT", "[\(device.name)] State: preparing (\(elapsed)ms)")

                    case .waiting(let error):
                        self?.rcLog("CONNECT", "[\(device.name)] State: waiting - \(error.localizedDescription) (\(elapsed)ms)", isWarning: true)

                    case .ready:
                        state.resumed = true
                        self?.connectedPeers.insert(device.id)
                        self?.recentlySeenDevices[device.id] = Date()
                        self?.rcLog("CONNECT", "[\(device.name)] State: READY (\(elapsed)ms)", details: "connectedPeers=\(self?.connectedPeers.count ?? 0)")
                        continuation.resume()

                    case .failed(let error):
                        state.resumed = true
                        self?.connections.removeValue(forKey: device.id)
                        self?.rcLog("CONNECT", "[\(device.name)] State: FAILED - \(error.localizedDescription) (\(elapsed)ms)", isError: true)
                        continuation.resume(throwing: error)

                    case .cancelled:
                        if !state.resumed {
                            state.resumed = true
                            self?.connections.removeValue(forKey: device.id)
                            self?.rcLog("CONNECT", "[\(device.name)] State: cancelled (\(elapsed)ms)", isWarning: true)
                            continuation.resume(throwing: CancellationError())
                        }

                    @unknown default:
                        self?.rcDebug("CONNECT", "[\(device.name)] State: unknown (\(elapsed)ms)")
                    }
                }
            }

            connection.start(queue: queue)
        }
    }

    /// Disconnect from a device.
    func disconnect(from deviceID: String) {
        let deviceName = deviceInfoCache[deviceID]?.name ?? deviceID
        guard let connection = connections[deviceID] else {
            rcDebug("CONNECT", "Cannot disconnect from \(deviceName) - no connection")
            return
        }

        rcLog("CONNECT", "Disconnecting from \(deviceName)")
        connection.cancel()
        connections.removeValue(forKey: deviceID)
        connectedPeers.remove(deviceID)
    }

    /// Disconnect from all devices.
    func disconnectAll() {
        for deviceID in connections.keys {
            disconnect(from: deviceID)
        }
    }

    private func setupConnectionHandlers(_ connection: NWConnection, isOutgoing: Bool, deviceID: String? = nil) {
        let connectionType = isOutgoing ? "outgoing" : "incoming"
        let deviceDesc = deviceID ?? "unknown"
        rcDebug("HANDLER", "Setting up \(connectionType) connection handlers for \(deviceDesc)")

        receiveMessage(on: connection)

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let deviceName = deviceID.flatMap { self.deviceInfoCache[$0]?.name } ?? deviceDesc

                switch state {
                case .ready:
                    self.rcLog("HANDLER", "[\(deviceName)] \(connectionType) connection ready")

                case .failed(let error):
                    self.rcLog("HANDLER", "[\(deviceName)] \(connectionType) connection FAILED: \(error.localizedDescription)", isError: true)
                    self.handleConnectionFailure(connection: connection, deviceID: deviceID, isOutgoing: isOutgoing)

                case .cancelled:
                    self.rcLog("HANDLER", "[\(deviceName)] \(connectionType) connection cancelled", isWarning: true)
                    self.handleConnectionFailure(connection: connection, deviceID: deviceID, isOutgoing: isOutgoing)

                case .waiting(let error):
                    self.rcLog("HANDLER", "[\(deviceName)] \(connectionType) connection waiting: \(error.localizedDescription)", isWarning: true)

                default:
                    break
                }
            }
        }
    }

    /// Handle connection failure/cancellation - factored out for clarity
    private func handleConnectionFailure(connection: NWConnection, deviceID: String?, isOutgoing: Bool) {
        if isOutgoing, let deviceID {
            connections.removeValue(forKey: deviceID)
            // Only remove from connectedPeers if there's no working incoming connection
            if incomingConnections[deviceID]?.state != .ready {
                connectedPeers.remove(deviceID)
                rcLog("HANDLER", "Removed \(deviceID) from connectedPeers (no working incoming connection)")
            } else {
                rcLog("HANDLER", "Outgoing to \(deviceID) failed, but incoming still ready")
            }
        }
        if !isOutgoing {
            pendingConnections.removeAll { $0 === connection }
            // Clean up from incomingConnections if tracked there
            for (id, conn) in incomingConnections where conn === connection {
                incomingConnections.removeValue(forKey: id)
                // Only remove from connectedPeers if there's no working outgoing connection
                if connections[id]?.state != .ready {
                    connectedPeers.remove(id)
                    rcLog("HANDLER", "Removed \(id) from connectedPeers (no working outgoing connection)")
                } else {
                    rcLog("HANDLER", "Incoming from \(id) failed, but outgoing still ready")
                }
                break
            }
        }
    }

    // MARK: - Message Sending

    /// Ensure we have a verified working connection to a device.
    /// If we haven't received from the device recently, send a ping and wait for response.
    /// Returns true if connection is verified, false if we couldn't establish one.
    func ensureConnection(to deviceID: String) async -> Bool {
        let deviceName = deviceInfoCache[deviceID]?.name ?? deviceID
        rcLog("VERIFY", "[\(deviceName)] Ensuring connection is alive")

        // Check if we have a recent verified connection
        if let lastSeen = recentlySeenDevices[deviceID],
           Date().timeIntervalSince(lastSeen) < 10 {
            // Connection was recently verified (received data within 10 seconds)
            let ago = Int(Date().timeIntervalSince(lastSeen))
            rcLog("VERIFY", "[\(deviceName)] Connection recently verified (\(ago)s ago) - skipping probe")
            return true
        }

        // Log current connection state
        let outgoingState = connections[deviceID].map { String(describing: $0.state) } ?? "nil"
        let incomingState = incomingConnections[deviceID].map { String(describing: $0.state) } ?? "nil"
        rcLog("VERIFY", "[\(deviceName)] Connection states: outgoing=\(outgoingState), incoming=\(incomingState)")

        // Check if we have an incoming connection (most reliable)
        if let incoming = incomingConnections[deviceID], incoming.state == .ready {
            // Incoming connection exists, send a quick ping to verify
            rcLog("VERIFY", "[\(deviceName)] Probing incoming connection...")
            let isAlive = await sendHealthCheckAndWaitForResponse(to: deviceID, using: incoming)
            if isAlive {
                rcLog("VERIFY", "[\(deviceName)] Incoming connection VERIFIED")
                return true
            }
            // Connection dead, clean it up
            rcLog("VERIFY", "[\(deviceName)] Incoming connection DEAD - cleaning up", isWarning: true)
            cleanupConnection(deviceID: deviceID, isOutgoing: false)
        }

        // Check if we have an outgoing connection
        if let outgoing = connections[deviceID], outgoing.state == .ready {
            rcLog("VERIFY", "[\(deviceName)] Probing outgoing connection...")
            let isAlive = await sendHealthCheckAndWaitForResponse(to: deviceID, using: outgoing)
            if isAlive {
                rcLog("VERIFY", "[\(deviceName)] Outgoing connection VERIFIED")
                return true
            }
            // Connection dead, clean it up
            rcLog("VERIFY", "[\(deviceName)] Outgoing connection DEAD - cleaning up", isWarning: true)
            cleanupConnection(deviceID: deviceID, isOutgoing: true)
        }

        // No verified connection - try to establish one
        if let device = discoveredDevices.first(where: { $0.id == deviceID }) {
            rcLog("VERIFY", "[\(deviceName)] No verified connection - attempting to establish new one")
            do {
                try await connect(to: device)
                // Wait a moment for the connection to stabilize
                try? await Task.sleep(for: .milliseconds(500))
                // Verify the new connection
                if let outgoing = connections[deviceID], outgoing.state == .ready {
                    rcLog("VERIFY", "[\(deviceName)] New connection ready - probing to verify...")
                    let isAlive = await sendHealthCheckAndWaitForResponse(to: deviceID, using: outgoing)
                    if isAlive {
                        rcLog("VERIFY", "[\(deviceName)] New connection VERIFIED")
                        return true
                    }
                    rcLog("VERIFY", "[\(deviceName)] New connection probe failed", isWarning: true)
                }
            } catch {
                rcLog("VERIFY", "[\(deviceName)] Failed to establish connection: \(error.localizedDescription)", isError: true)
            }
        } else {
            rcLog("VERIFY", "[\(deviceName)] Device not in discovered list - cannot establish connection", isWarning: true)
        }

        rcLog("VERIFY", "[\(deviceName)] Could not establish verified connection", isError: true)
        return false
    }

    /// Send a command to a specific device. Automatically retries once on connection failure.
    func send(command: RemoteControlCommand, to deviceID: String) async throws {
        try await sendWithRetry(command: command, to: deviceID, isRetry: false)
    }

    /// Internal send with retry logic.
    private func sendWithRetry(command: RemoteControlCommand, to deviceID: String, isRetry: Bool) async throws {
        let deviceName = deviceInfoCache[deviceID]?.name ?? deviceID
        let commandDesc = String(describing: command).prefix(50)

        // Find a ready connection - prefer ready connections over non-ready ones
        let outgoingConnection = connections[deviceID]
        let incomingConnection = incomingConnections[deviceID]

        // Log available connections for debugging
        let outgoingState = outgoingConnection.map { String(describing: $0.state) } ?? "nil"
        let incomingState = incomingConnection.map { String(describing: $0.state) } ?? "nil"
        rcDebug("SEND", "[\(deviceName)] Preparing send: outgoing=\(outgoingState), incoming=\(incomingState)")

        // Check if we've received data from this device recently (connection is verified alive)
        let lastSeen = recentlySeenDevices[deviceID]
        let connectionIsRecent = lastSeen.map { Date().timeIntervalSince($0) < 30 } ?? false

        // Choose the best available connection:
        // 1. Prefer ready incoming connection (we know it works - remote device initiated it)
        // 2. Fall back to ready outgoing connection (if recently verified alive)
        // 3. Fall back to any ready connection
        // 4. Fall back to any connection (will fail the state check below)
        let connection: NWConnection?
        let isOutgoing: Bool
        let connectionType: String

        if let incoming = incomingConnection, incoming.state == .ready {
            // Incoming connections are most reliable - we received data on them
            connection = incoming
            isOutgoing = false
            connectionType = "incoming"
            rcDebug("SEND", "[\(deviceName)] Selected ready incoming connection")
        } else if let outgoing = outgoingConnection, outgoing.state == .ready, connectionIsRecent {
            // Outgoing is OK if we've received from device recently (proving it's alive)
            connection = outgoing
            isOutgoing = true
            connectionType = "outgoing"
            rcDebug("SEND", "[\(deviceName)] Selected ready outgoing connection (recently verified)")
        } else if let outgoing = outgoingConnection, outgoing.state == .ready {
            // Use outgoing even if not recently verified (will reconnect on failure)
            connection = outgoing
            isOutgoing = true
            connectionType = "outgoing"
            rcDebug("SEND", "[\(deviceName)] Selected ready outgoing connection (not recently verified)")
        } else {
            // Fall back to any available connection
            connection = incomingConnection ?? outgoingConnection
            isOutgoing = outgoingConnection != nil && incomingConnection == nil
            connectionType = isOutgoing ? "outgoing" : "incoming"
            rcDebug("SEND", "[\(deviceName)] No ready connection, falling back to \(connectionType)")
        }

        guard let connection else {
            // If no connection and this isn't a retry, try to establish one
            if !isRetry, let device = discoveredDevices.first(where: { $0.id == deviceID }) {
                rcLog("SEND", "[\(deviceName)] No connection - attempting to connect...", isWarning: true)
                do {
                    try await connect(to: device)
                    try await sendWithRetry(command: command, to: deviceID, isRetry: true)
                    return
                } catch {
                    rcLog("SEND", "[\(deviceName)] Failed to connect: \(error.localizedDescription)", isError: true)
                    throw RemoteControlError.notConnected
                }
            }
            rcLog("SEND", "[\(deviceName)] Cannot send - no connection available", isError: true, details: "outgoing=[\(connections.keys.joined(separator: ", "))], incoming=[\(incomingConnections.keys.joined(separator: ", "))]")
            throw RemoteControlError.notConnected
        }

        // Check connection state before attempting to send
        guard connection.state == .ready else {
            rcLog("SEND", "[\(deviceName)] Connection not ready (state=\(connection.state)) - cleaning up", isWarning: true)
            cleanupConnection(deviceID: deviceID, isOutgoing: isOutgoing)

            // If this isn't a retry, try to reconnect
            if !isRetry, let device = discoveredDevices.first(where: { $0.id == deviceID }) {
                rcLog("SEND", "[\(deviceName)] Attempting reconnect...")
                do {
                    try await connect(to: device)
                    try await sendWithRetry(command: command, to: deviceID, isRetry: true)
                    return
                } catch {
                    rcLog("SEND", "[\(deviceName)] Reconnect failed: \(error.localizedDescription)", isError: true)
                }
            }
            throw RemoteControlError.notConnected
        }

        rcLog("SEND", "[\(deviceName)] Sending \(commandDesc) via \(connectionType)\(isRetry ? " (retry)" : "")")

        let message = RemoteControlMessage(
            senderDeviceID: self.deviceID,
            senderDeviceName: self.deviceName,
            senderPlatform: .current,
            targetDeviceID: deviceID,
            command: command
        )

        do {
            try await sendMessage(message, on: connection, deviceName: deviceName)
            rcLog("SEND", "[\(deviceName)] Send completed via \(connectionType)")
            // Update recently seen on successful send
            recentlySeenDevices[deviceID] = Date()
        } catch {
            rcLog("SEND", "[\(deviceName)] Send failed: \(error.localizedDescription)", isError: true)
            cleanupConnection(deviceID: deviceID, isOutgoing: isOutgoing)

            // If this isn't a retry, try to reconnect and resend
            if !isRetry, let device = discoveredDevices.first(where: { $0.id == deviceID }) {
                rcLog("SEND", "[\(deviceName)] Attempting reconnect and resend...")
                do {
                    try await connect(to: device)
                    try await sendWithRetry(command: command, to: deviceID, isRetry: true)
                    return
                } catch {
                    rcLog("SEND", "[\(deviceName)] Reconnect and resend failed: \(error.localizedDescription)", isError: true)
                }
            }
            throw error
        }
    }

    /// Clean up a dead connection.
    private func cleanupConnection(deviceID: String, isOutgoing: Bool) {
        let deviceName = deviceInfoCache[deviceID]?.name ?? deviceID
        let connectionType = isOutgoing ? "outgoing" : "incoming"

        if isOutgoing {
            connections[deviceID]?.cancel()
            connections.removeValue(forKey: deviceID)
            // Only remove from connectedPeers if there's no working incoming connection
            if incomingConnections[deviceID]?.state != .ready {
                connectedPeers.remove(deviceID)
                rcLog("CLEANUP", "[\(deviceName)] Cleaned up \(connectionType), removed from connectedPeers")
            } else {
                rcLog("CLEANUP", "[\(deviceName)] Cleaned up \(connectionType), but incoming still ready")
            }
        } else {
            incomingConnections[deviceID]?.cancel()
            incomingConnections.removeValue(forKey: deviceID)
            // Only remove from connectedPeers if there's no working outgoing connection
            if connections[deviceID]?.state != .ready {
                connectedPeers.remove(deviceID)
                rcLog("CLEANUP", "[\(deviceName)] Cleaned up \(connectionType), removed from connectedPeers")
            } else {
                rcLog("CLEANUP", "[\(deviceName)] Cleaned up \(connectionType), but outgoing still ready")
            }
        }
        // Allow re-probing this device next time it's discovered
        probedDevices.remove(deviceID)
    }

    /// Broadcast a command to all connected devices.
    func broadcast(command: RemoteControlCommand) async {
        let message = RemoteControlMessage(
            senderDeviceID: deviceID,
            senderDeviceName: deviceName,
            senderPlatform: .current,
            targetDeviceID: nil,
            command: command
        )

        // Collect device IDs that need cleanup
        var deadOutgoingConnections: [String] = []
        var deadIncomingConnections: [String] = []

        // Send to all outgoing connections
        for (deviceID, connection) in connections {
            let deviceName = deviceInfoCache[deviceID]?.name ?? deviceID
            guard connection.state == .ready else {
                rcDebug("BROADCAST", "[\(deviceName)] Skipping non-ready outgoing (state=\(connection.state))")
                deadOutgoingConnections.append(deviceID)
                continue
            }
            do {
                try await sendMessage(message, on: connection, deviceName: deviceName)
            } catch {
                rcLog("BROADCAST", "[\(deviceName)] Failed via outgoing: \(error.localizedDescription)", isWarning: true)
                deadOutgoingConnections.append(deviceID)
            }
        }

        // Send to all tracked incoming connections
        for (deviceID, connection) in incomingConnections {
            let deviceName = deviceInfoCache[deviceID]?.name ?? deviceID
            guard connection.state == .ready else {
                rcDebug("BROADCAST", "[\(deviceName)] Skipping non-ready incoming (state=\(connection.state))")
                deadIncomingConnections.append(deviceID)
                continue
            }
            do {
                try await sendMessage(message, on: connection, deviceName: deviceName)
            } catch {
                rcLog("BROADCAST", "[\(deviceName)] Failed via incoming: \(error.localizedDescription)", isWarning: true)
                deadIncomingConnections.append(deviceID)
            }
        }

        // Send to any unidentified pending connections
        for connection in pendingConnections {
            if connection.state == .ready {
                try? await sendMessage(message, on: connection, deviceName: "pending")
            }
        }

        // Clean up dead connections
        for deviceID in deadOutgoingConnections {
            let deviceName = deviceInfoCache[deviceID]?.name ?? deviceID
            rcLog("BROADCAST", "[\(deviceName)] Cleaning up dead outgoing connection")
            connections[deviceID]?.cancel()
            connections.removeValue(forKey: deviceID)
            connectedPeers.remove(deviceID)
        }

        for deviceID in deadIncomingConnections {
            let deviceName = deviceInfoCache[deviceID]?.name ?? deviceID
            rcLog("BROADCAST", "[\(deviceName)] Cleaning up dead incoming connection")
            incomingConnections[deviceID]?.cancel()
            incomingConnections.removeValue(forKey: deviceID)
            connectedPeers.remove(deviceID)
        }

        // Clean up non-ready pending connections
        let deadPending = pendingConnections.filter { $0.state != .ready && $0.state != .setup && $0.state != .preparing }
        if !deadPending.isEmpty {
            rcDebug("BROADCAST", "Cleaning up \(deadPending.count) dead pending connections")
        }
        for connection in deadPending {
            connection.cancel()
        }
        pendingConnections.removeAll { $0.state != .ready && $0.state != .setup && $0.state != .preparing }

        rcDebug("BROADCAST", "Broadcast complete")
    }

    private func sendMessage(_ message: RemoteControlMessage, on connection: NWConnection, deviceName: String? = nil) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        let name = deviceName ?? message.targetDeviceID ?? "unknown"

        // Length-prefix framing: 4 bytes for length + data
        var length = UInt32(data.count).bigEndian
        var framedData = Data(bytes: &length, count: 4)
        framedData.append(data)

        rcDebug("SEND", "[\(name)] Sending \(framedData.count) bytes (4 header + \(data.count) payload)")

        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: framedData, completion: .contentProcessed { [weak self] error in
                Task { @MainActor [weak self] in
                    if let error {
                        self?.rcLog("SEND", "[\(name)] TCP send failed: \(error.localizedDescription)", isError: true)
                        continuation.resume(throwing: error)
                    } else {
                        self?.rcDebug("SEND", "[\(name)] TCP send completed")
                        continuation.resume()
                    }
                }
            })
        }
    }

    // MARK: - Message Receiving

    private func receiveMessage(on connection: NWConnection) {
        // First, read the 4-byte length prefix
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let error {
                Task { @MainActor in
                    self.rcLog("RECV", "Header receive error: \(error.localizedDescription)", isError: true)
                }
                return
            }

            if isComplete {
                Task { @MainActor in
                    self.rcDebug("RECV", "Connection completed (EOF)")
                }
                return
            }

            guard let lengthData = content, lengthData.count == 4 else {
                // Continue receiving
                Task { @MainActor in
                    self.receiveMessage(on: connection)
                }
                return
            }

            // Parse length
            let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

            Task { @MainActor in
                self.rcDebug("RECV", "Reading message body: \(length) bytes")
            }

            // Read the message body
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] content, _, _, error in
                guard let self else { return }

                if let error {
                    Task { @MainActor in
                        self.rcLog("RECV", "Body receive error: \(error.localizedDescription)", isError: true)
                    }
                    return
                }

                if let data = content {
                    Task { @MainActor in
                        self.handleReceivedData(data, from: connection)
                    }
                }

                // Continue receiving next message
                Task { @MainActor in
                    self.receiveMessage(on: connection)
                }
            }
        }
    }

    private func handleReceivedData(_ data: Data, from connection: NWConnection) {
        do {
            let decoder = JSONDecoder()
            let message = try decoder.decode(RemoteControlMessage.self, from: data)
            let senderName = message.senderDeviceName ?? message.senderDeviceID
            let commandDesc = String(describing: message.command).prefix(50)

            // Ignore our own messages
            guard message.senderDeviceID != deviceID else {
                rcDebug("RECV", "Ignoring own message from \(senderName)")
                return
            }

            // Check if message is for us (or broadcast)
            if let targetID = message.targetDeviceID, targetID != deviceID {
                rcDebug("RECV", "Ignoring message from \(senderName) targeted at \(targetID)")
                return
            }

            // Determine connection type for logging
            let isOutgoing = connections.values.contains(where: { $0 === connection })
            let connectionType = isOutgoing ? "outgoing" : "incoming"
            rcLog("RECV", "[\(senderName)] Received \(commandDesc) via \(connectionType)", details: "\(data.count) bytes")

            // Track this incoming connection by sender device ID for bidirectional communication
            Task { @MainActor in
                // Always track incoming connections - they're useful even if we have outgoing ones
                // (the outgoing might not be ready yet, but the incoming is proven to work since we just received on it)
                if self.incomingConnections[message.senderDeviceID] !== connection {
                    self.incomingConnections[message.senderDeviceID] = connection
                    self.connectedPeers.insert(message.senderDeviceID)
                    self.rcLog("RECV", "[\(senderName)] Tracked incoming connection", details: "connectedPeers=\(self.connectedPeers.count)")
                }

                // Track when we last saw this device (for preservation after connection cleanup)
                self.recentlySeenDevices[message.senderDeviceID] = Date()
                // Clear first-seen since device is responsive
                self.deviceFirstSeen.removeValue(forKey: message.senderDeviceID)
                self.rcDebug("RECV", "[\(senderName)] Updated recently-seen timestamp")

                // Update discovered device info if we got name/platform from the message
                if let senderName = message.senderDeviceName, let senderPlatform = message.senderPlatform {
                    self.updateDiscoveredDeviceInfo(
                        deviceID: message.senderDeviceID,
                        name: senderName,
                        platform: senderPlatform
                    )
                }

                // Emit to the commands stream
                self.commandsContinuation?.yield(message)
            }

        } catch {
            rcLog("RECV", "Failed to decode message: \(error.localizedDescription)", isError: true, details: "\(data.count) bytes")
        }
    }

    /// Update a discovered device with info from a message (when TXT record wasn't available).
    /// If the device isn't in the list, add it (handles case where device connects before Bonjour discovers it).
    private func updateDiscoveredDeviceInfo(deviceID: String, name: String, platform: DevicePlatform) {
        // Always update the cache so info is preserved across browse result changes
        deviceInfoCache[deviceID] = (name: name, platform: platform)

        if let index = discoveredDevices.firstIndex(where: { $0.id == deviceID }) {
            let existing = discoveredDevices[index]
            // Only update if the name was just the UUID (placeholder)
            if existing.name == deviceID || existing.name != name {
                discoveredDevices[index] = DiscoveredDevice(
                    id: deviceID,
                    name: name,
                    platform: platform,
                    currentVideoTitle: existing.currentVideoTitle,
                    currentChannelName: existing.currentChannelName,
                    currentVideoThumbnailURL: existing.currentVideoThumbnailURL,
                    isPlaying: existing.isPlaying
                )
                rcLog("DEVICE", "Updated device info for \(deviceID): \(name) (\(platform.rawValue))")
            }
        } else {
            // Device not in list yet (connected before Bonjour discovered it) - add it
            let device = DiscoveredDevice(
                id: deviceID,
                name: name,
                platform: platform,
                currentVideoTitle: nil,
                currentChannelName: nil,
                currentVideoThumbnailURL: nil,
                isPlaying: false
            )
            discoveredDevices.append(device)
            rcLog("DEVICE", "Added device from incoming connection: \(name) (\(platform.rawValue))")
        }
    }

    /// Update a discovered device with playback state from a state update message.
    func updateDiscoveredDevicePlaybackState(deviceID: String, videoTitle: String?, channelName: String?, thumbnailURL: URL?, isPlaying: Bool) {
        if let index = discoveredDevices.firstIndex(where: { $0.id == deviceID }) {
            let existing = discoveredDevices[index]
            discoveredDevices[index] = DiscoveredDevice(
                id: deviceID,
                name: existing.name,
                platform: existing.platform,
                currentVideoTitle: videoTitle,
                currentChannelName: channelName,
                currentVideoThumbnailURL: thumbnailURL,
                isPlaying: isPlaying
            )
        } else if let cachedInfo = deviceInfoCache[deviceID] {
            // Device not in list but we have cached info - add it
            let device = DiscoveredDevice(
                id: deviceID,
                name: cachedInfo.name,
                platform: cachedInfo.platform,
                currentVideoTitle: videoTitle,
                currentChannelName: channelName,
                currentVideoThumbnailURL: thumbnailURL,
                isPlaying: isPlaying
            )
            discoveredDevices.append(device)
            rcLog("DEVICE", "Added device from state update: \(cachedInfo.name)")
        }
    }
}

// MARK: - Errors

enum RemoteControlError: LocalizedError {
    case notConnected
    case connectionFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to device"
        case .connectionFailed:
            return "Failed to connect to device"
        case .encodingFailed:
            return "Failed to encode message"
        }
    }
}
