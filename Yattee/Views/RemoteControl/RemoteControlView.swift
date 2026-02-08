//
//  RemoteControlView.swift
//  Yattee
//
//  View for controlling playback on a remote device.
//

import SwiftUI

struct RemoteControlView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sheetContentHeight) private var sheetContentHeight

    let device: DiscoveredDevice

    /// Preview mode forces content visibility and provides mock state.
    private let previewMode: Bool

    init(device: DiscoveredDevice, previewMode: Bool = false) {
        self.device = device
        self.previewMode = previewMode
    }

    @State private var isConnecting = false
    @State private var isConnected = false
    @State private var connectionError: String?
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0
    @State private var isAdjustingVolume = false
    @State private var adjustedVolume: Float = 1.0

    // Local time estimation for smooth scrubber updates
    @State private var estimatedCurrentTime: TimeInterval = 0
    @State private var playbackTimer: Timer?
    @State private var lastSyncedVideoID: String?

    /// Tick to force view refresh for computed properties like deviceStatus.
    @State private var refreshTick: Int = 0

    // Symbol effect triggers
    @State private var seekBackwardTrigger = 0
    @State private var seekForwardTrigger = 0
    @State private var playPreviousTapCount = 0
    @State private var playNextTapCount = 0

    private var remoteControl: RemoteControlCoordinator? {
        appEnvironment?.remoteControlCoordinator
    }

    private var networkService: LocalNetworkService? {
        appEnvironment?.localNetworkService
    }

    /// The remote device's player state from the coordinator.
    private var remoteState: RemotePlayerState {
        if previewMode {
            return Self.previewState
        }
        return remoteControl?.remoteDeviceStates[device.id] ?? .idle
    }

    /// Mock state for SwiftUI previews.
    private static let previewState = RemotePlayerState(
        videoID: "preview-video",
        videoTitle: "Sample Video Title - How to Build Amazing Apps",
        channelName: "Sample Channel",
        thumbnailURL: URL(string: "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg"),
        currentTime: 150,
        duration: 600,
        isPlaying: true,
        rate: 1.0,
        volume: 0.75,
        isMuted: false,
        volumeMode: "mpv",
        isFullscreen: false,
        canToggleFullscreen: true,
        hasPrevious: true,
        hasNext: true
    )

    /// Whether we're actually connected to this device (from the network service).
    private var isActuallyConnected: Bool {
        networkService?.connectedPeers.contains(device.id) ?? false
    }

    /// Current device status from network service.
    private var deviceStatus: LocalNetworkService.DeviceStatus {
        if previewMode {
            return .connected
        }
        return networkService?.deviceStatus(for: device.id) ?? .discoveredOnly
    }

    /// Current time to display (uses local estimation for smooth updates).
    private var displayCurrentTime: TimeInterval {
        if isScrubbing {
            return scrubTime
        }
        return min(estimatedCurrentTime, remoteState.duration)
    }

    /// Whether to show volume controls (only when remote device accepts volume control).
    /// Uses the remote device's volume mode - if system mode, hide volume controls.
    private var showVolumeControls: Bool {
        remoteState.acceptsVolumeControl
    }

    /// Current playback rate from remote state, converted to PlaybackRate enum.
    private var currentPlaybackRate: PlaybackRate {
        PlaybackRate(rawValue: Double(remoteState.rate)) ?? .x1
    }

    /// Calculate content height for sheet sizing.
    private var calculatedHeight: CGFloat {
        var height: CGFloat = 100 // Base: nav bar + padding

        if previewMode || isActuallyConnected || isConnected {
            height += 200 // Now playing section (thumbnail + info + scrubber)
            height += 100 // Playback controls
            if showVolumeControls {
                height += 60 // Volume controls
            }
            height += 60 // Playback rate controls
        } else {
            height += 200 // Offline view
        }

        return height
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Show controls if we're connected OR if we have local state that says we were connected
                if previewMode || isActuallyConnected || isConnected {
                    nowPlayingSection
                    playbackControls
                    if showVolumeControls {
                        volumeControls
                    }
                    playbackRateControls
                } else if case .recentlySeen = deviceStatus {
                    // Device went offline - show reconnect option
                    offlineView
                }
            }
            .padding()
        }
        .navigationTitle(device.name)
        
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 400)
        #endif
        .task {
            await connect()
        }
        .onAppear {
            startPlaybackTimer()
            sheetContentHeight?.wrappedValue = calculatedHeight
        }
        .onDisappear {
            stopPlaybackTimer()
        }
        .onChange(of: remoteState) { _, newState in
            syncWithRemoteState(newState)
        }
        .onChange(of: showVolumeControls) { _, _ in
            sheetContentHeight?.wrappedValue = calculatedHeight
        }
        .onChange(of: isActuallyConnected) { _, newValue in
            // Update local state when connection status changes
            if newValue {
                isConnected = true
                connectionError = nil
            } else if isConnected {
                // We lost connection - mark as disconnected
                isConnected = false
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                deviceHeader
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    Task {
                        await remoteControl?.closeVideo(on: device)
                        dismiss()
                    }
                } label: {
                    Label(String(localized: "remoteControl.closeVideo"), systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .disabled(remoteState.videoID == nil)
            }
        }
    }

    // MARK: - Offline View

    @ViewBuilder
    private var offlineView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(String(localized: "remoteControl.deviceOffline"))
                .font(.headline)

            Text(String(localized: "remoteControl.deviceOfflineMessage"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await connect() }
            } label: {
                Label(String(localized: "remoteControl.tryReconnect"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Playback Timer

    private func startPlaybackTimer() {
        // Update estimated time every 0.1 seconds for smooth scrubber movement
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                guard !isScrubbing else { return }

                if remoteState.isPlaying && remoteState.duration > 0 {
                    let increment = 0.1 * Double(remoteState.rate)
                    estimatedCurrentTime = min(estimatedCurrentTime + increment, remoteState.duration)
                }

                // Increment refresh tick every 10 iterations (once per second) to update status display
                if Int(Date().timeIntervalSince1970 * 10) % 10 == 0 {
                    refreshTick += 1
                }
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func syncWithRemoteState(_ state: RemotePlayerState) {
        // Trigger view refresh for computed properties that depend on remoteState
        refreshTick += 1

        // If video changed, reset estimated time
        if state.videoID != lastSyncedVideoID {
            lastSyncedVideoID = state.videoID
            estimatedCurrentTime = state.currentTime
            return
        }

        // Sync local estimate with remote state
        estimatedCurrentTime = state.currentTime
    }

    // MARK: - Device Header (Compact)

    @ViewBuilder
    private var deviceHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: device.platform.iconName)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)
                Text(device.platform.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Connection status - use actual network service status
            connectionStatusView
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        // refreshTick triggers re-render for live status updates
        let _ = refreshTick

        if isConnecting {
            ProgressView()
                .controlSize(.small)
        } else if connectionError != nil {
            Button {
                connectionError = nil
                Task { await connect() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(String(localized: "common.retry"))
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            // Use device status from network service
            switch deviceStatus {
            case .connected:
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.green)
                }
            case .recentlySeen(let ago):
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                        Text(String(localized: "remoteControl.status.offline"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(Int(ago))s ago")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            case .discoveredOnly:
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "remoteControl.status.discovered"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Now Playing Section

    @ViewBuilder
    private var nowPlayingSection: some View {
        VStack(spacing: 12) {
            HStack {
                // Thumbnail - only show if there's an active video
                if remoteState.videoID != nil,
                   let thumbnailURL = remoteState.thumbnailURL ?? device.currentVideoThumbnailURL {
                    AsyncImage(url: thumbnailURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16/9, contentMode: .fit)
                                .clipShape(.rect(cornerRadius: 8))
                        case .failure:
                            thumbnailPlaceholder
                        case .empty:
                            thumbnailPlaceholder
                                .overlay(ProgressView())
                        @unknown default:
                            thumbnailPlaceholder
                        }
                    }
                    .frame(maxWidth: 120)
                } else {
                    thumbnailPlaceholder
                        .frame(maxWidth: 120)
                }
                
                // Video info - only show details if there's an active video
                VStack(alignment: .leading, spacing: 4) {
                    if remoteState.videoID != nil {
                        Text(remoteState.videoTitle ?? device.currentVideoTitle ?? String(localized: "remoteControl.noVideo"))
                            .font(.headline)
                            .lineLimit(2)
                        
                        if let channel = remoteState.channelName {
                            Text(channel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(String(localized: "remoteControl.noVideo"))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Scrubber
            VStack(spacing: 4) {
                #if os(tvOS)
                ProgressView(value: displayCurrentTime, total: max(remoteState.duration, 1))
                    .tint(.accentColor)
                #else
                Slider(
                    value: Binding(
                        get: { displayCurrentTime },
                        set: { newValue in
                            scrubTime = newValue
                            if !isScrubbing {
                                isScrubbing = true
                            }
                        }
                    ),
                    in: 0...max(remoteState.duration, 1),
                    onEditingChanged: { editing in
                        if !editing {
                            // User released - send seek command
                            estimatedCurrentTime = scrubTime
                            Task {
                                await remoteControl?.seek(to: scrubTime, on: device)
                            }
                            isScrubbing = false
                        }
                    }
                )
                .tint(.accentColor)
                .disabled(remoteState.duration == 0)
                #endif

                HStack {
                    Text(formatTime(displayCurrentTime))
                    Spacer()
                    Text("-" + formatTime(remoteState.duration - displayCurrentTime))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(.quaternary)
            .aspectRatio(16/9, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                Image(systemName: "play.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
    }

    // MARK: - Playback Controls

    @ViewBuilder
    private var playbackControls: some View {
        VStack {
            HStack(spacing: 24) {
                // Play previous
                Button {
                    playPreviousTapCount += 1
                    Task {
                        await remoteControl?.playPrevious(on: device)
                    }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title)
                        .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: playPreviousTapCount)
                }
                .buttonStyle(.plain)
                .disabled(!remoteState.hasPrevious)
                .opacity(remoteState.hasPrevious ? 1.0 : 0.3)
                
                // Seek backward
                Button {
                    seekBackwardTrigger += 1
                    Task {
                        let newTime = max(0, remoteState.currentTime - 10)
                        await remoteControl?.seek(to: newTime, on: device)
                    }
                } label: {
                    Image(systemName: "10.arrow.trianglehead.counterclockwise")
                        .font(.title)
                        .symbolEffect(.rotate.byLayer, options: .speed(2).nonRepeating, value: seekBackwardTrigger)
                }
                .buttonStyle(.plain)
                
                // Play/Pause
                Button {
                    Task {
                        await remoteControl?.togglePlayPause(on: device)
                    }
                } label: {
                    Image(systemName: remoteState.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .contentTransition(.symbolEffect(.replace, options: .speed(2)))
                }
                .buttonStyle(.plain)
                
                // Seek forward
                Button {
                    seekForwardTrigger += 1
                    Task {
                        let newTime = min(remoteState.duration, remoteState.currentTime + 10)
                        await remoteControl?.seek(to: newTime, on: device)
                    }
                } label: {
                    Image(systemName: "10.arrow.trianglehead.clockwise")
                        .font(.title)
                        .symbolEffect(.rotate.byLayer, options: .speed(2).nonRepeating, value: seekForwardTrigger)
                }
                .buttonStyle(.plain)
                
                // Play next
                Button {
                    playNextTapCount += 1
                    Task {
                        await remoteControl?.playNext(on: device)
                    }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title)
                        .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: playNextTapCount)
                }
                .buttonStyle(.plain)
                .disabled(!remoteState.hasNext)
                .opacity(remoteState.hasNext ? 1.0 : 0.3)
            }
            .padding()
        }
    }

    // MARK: - Volume Controls

    @ViewBuilder
    private var volumeControls: some View {
        // refreshTick triggers re-render for live state updates
        let _ = refreshTick

        VStack(spacing: 8) {
            #if !os(tvOS)
            HStack {
                Button {
                    Task {
                        await remoteControl?.setMuted(!remoteState.isMuted, on: device)
                    }
                } label: {
                    Image(systemName: remoteState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(remoteState.isMuted ? .red : .secondary)
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { Double(isAdjustingVolume ? adjustedVolume : remoteState.volume) },
                        set: { newValue in
                            adjustedVolume = Float(newValue)
                            if !isAdjustingVolume {
                                isAdjustingVolume = true
                            }
                        }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if !editing {
                            // User released - send volume command
                            Task {
                                await remoteControl?.setVolume(adjustedVolume, on: device)
                            }
                            isAdjustingVolume = false
                        }
                    }
                )
                .disabled(remoteState.isMuted)
            }
            #endif
        }
        .padding([.horizontal, .bottom])
    }

    // MARK: - Playback Rate Controls

    @ViewBuilder
    private var playbackRateControls: some View {
        HStack {
            Label(String(localized: "player.quality.playbackSpeed"), systemImage: "gauge.with.needle")
                .font(.headline)

            Spacer()

            HStack(spacing: 8) {
                Button {
                    if let newRate = previousRate() {
                        Task {
                            await remoteControl?.setRate(Float(newRate.rawValue), on: device)
                        }
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.body.weight(.medium))
                        .frame(minWidth: 18, minHeight: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .disabled(previousRate() == nil)

                Menu {
                    ForEach(PlaybackRate.allCases) { rate in
                        Button {
                            Task {
                                await remoteControl?.setRate(Float(rate.rawValue), on: device)
                            }
                        } label: {
                            if currentPlaybackRate == rate {
                                Label(rate.displayText, systemImage: "checkmark")
                            } else {
                                Text(rate.displayText)
                            }
                        }
                    }
                } label: {
                    Text(currentPlaybackRate.displayText)
                        .font(.body.weight(.medium))
                        .frame(minWidth: 60)
                }

                Button {
                    if let newRate = nextRate() {
                        Task {
                            await remoteControl?.setRate(Float(newRate.rawValue), on: device)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.medium))
                        .frame(minWidth: 18, minHeight: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .disabled(nextRate() == nil)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func connect() async {
        isConnecting = true
        connectionError = nil

        do {
            try await remoteControl?.connect(to: device)
            isConnected = true
        } catch {
            connectionError = error.localizedDescription
        }

        isConnecting = false
    }

    private func disconnect() {
        remoteControl?.disconnect(from: device)
        isConnected = false
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// Returns the previous playback rate, or nil if at minimum.
    private func previousRate() -> PlaybackRate? {
        let allRates = PlaybackRate.allCases
        guard let currentIndex = allRates.firstIndex(of: currentPlaybackRate),
              currentIndex > 0 else {
            return nil
        }
        return allRates[currentIndex - 1]
    }

    /// Returns the next playback rate, or nil if at maximum.
    private func nextRate() -> PlaybackRate? {
        let allRates = PlaybackRate.allCases
        guard let currentIndex = allRates.firstIndex(of: currentPlaybackRate),
              currentIndex < allRates.count - 1 else {
            return nil
        }
        return allRates[currentIndex + 1]
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        RemoteControlView(device: DiscoveredDevice(
            id: "preview-device",
            name: "Preview Mac",
            platform: .macOS,
            currentVideoTitle: "Sample Video Title",
            currentChannelName: "Sample Channel",
            currentVideoThumbnailURL: nil,
            isPlaying: true
        ),
        previewMode: true)
    }
    .appEnvironment(.preview)
}
