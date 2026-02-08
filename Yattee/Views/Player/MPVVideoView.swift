//
//  MPVVideoView.swift
//  Yattee
//
//  SwiftUI view that displays MPV video with custom controls overlay.
//

import SwiftUI

#if os(iOS) || os(macOS) || os(tvOS)

/// SwiftUI view that wraps MPV video rendering with custom controls.
struct MPVVideoView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    let backend: MPVBackend
    @Bindable var playerState: PlayerState
    let playerService: PlayerService

    /// Whether to show playback controls
    var showsControls: Bool = true

    /// Whether to apply aspect ratio (enable when this view controls its own size)
    var appliesAspectRatio: Bool = false

    /// Whether this view is in widescreen layout mode
    var isWideScreenLayout: Bool = false

    /// Whether to show the debug overlay (disable when parent handles it)
    var showsDebugOverlay: Bool = true

    /// Callback for toggling panel visibility (widescreen layout)
    var onTogglePanel: (() -> Void)? = nil

    /// Whether panel is currently visible (widescreen layout)
    var isPanelVisible: Bool = true

    /// Which side the panel is on (widescreen layout)
    var panelSide: FloatingPanelSide = .right

    /// Callback for closing the video
    var onClose: (() -> Void)? = nil

    /// Callback for toggling fullscreen (widescreen videos only)
    var onToggleFullscreen: (() -> Void)? = nil

    /// Whether currently in fullscreen mode
    var isFullscreen: Bool = false

    /// Whether current video is widescreen (aspect ratio > 1.0)
    var isWidescreenVideo: Bool = false

    #if os(iOS)
    /// Callback for toggling orientation lock
    var onToggleOrientationLock: (() -> Void)? = nil

    /// Whether orientation is currently locked
    var isOrientationLocked: Bool = false

    /// Callback for toggling details visibility (fullscreen in portrait)
    var onToggleDetailsVisibility: (() -> Void)? = nil

    /// Callback for showing queue management sheet
    var onShowQueue: (() -> Void)? = nil
    #endif

    /// Debug stats for overlay (updated periodically when visible)
    @State private var debugStats: MPVDebugStats = MPVDebugStats()

    /// Timer for updating debug stats
    @State private var debugUpdateTimer: Timer?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                // MPV render surface - always show (fullscreen is now within the same view hierarchy)
                MPVRenderViewRepresentable(
                    backend: backend,
                    playerState: playerState
                )
                .frame(width: width, height: height)
                .background(Color.black)
                
                // Loading overlay - shown only if backend setup is not complete
                // (should be rare since backends are pre-warmed at app launch)
                if !backend.isSetupComplete {
                    Color.black
                        .overlay(
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                                Text("Initializing player...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        )
                        .transition(.opacity)
                        .zIndex(100)
                }

                // Custom controls overlay (MPV has no native controls)
                // Hide during PiP or when debug overlay is shown
                if showsControls && playerState.pipState != .active && !playerState.showDebugOverlay {
                    controlsView
                        .frame(width: width, height: height)
                }

                // Debug overlay - show when enabled and not in widescreen (widescreen has its own)
                if showsDebugOverlay && !isWideScreenLayout {
                    // Tap anywhere to dismiss
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            playerState.showDebugOverlay = false
                        }
                        .opacity(playerState.showDebugOverlay ? 1 : 0)
                        .allowsHitTesting(playerState.showDebugOverlay)

                    VStack {
                        HStack {
                            MPVDebugOverlay(
                                stats: debugStats,
                                isVisible: $playerState.showDebugOverlay,
                                isLandscape: false
                            )
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(12)
                    .allowsHitTesting(false)
                    .opacity(playerState.showDebugOverlay ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: playerState.showDebugOverlay)
                }
            }
            .frame(width: width, height: height)
        }
        .modifier(ConditionalAspectRatio(
            ratio: playerState.displayAspectRatio,
            applies: appliesAspectRatio
        ))
        .onAppear {
            // Start debug updates if overlay is already visible when view appears
            if playerState.showDebugOverlay {
                startDebugUpdates()
            }
        }
        .onChange(of: playerState.showDebugOverlay) { _, isVisible in
            if isVisible {
                startDebugUpdates()
            } else {
                stopDebugUpdates()
            }
        }
        .onDisappear {
            stopDebugUpdates()
        }
    }

    private func startDebugUpdates() {
        // Stop any existing timer first
        stopDebugUpdates()

        // Update immediately
        debugStats = backend.getDebugStats()

        // Then update every second
        debugUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                self.debugStats = self.backend.getDebugStats()
            }
        }
    }

    private func stopDebugUpdates() {
        debugUpdateTimer?.invalidate()
        debugUpdateTimer = nil
    }

    // MARK: - Controls View

    @ViewBuilder
    private var controlsView: some View {
        #if os(iOS)
        PlayerControlsView(
            playerState: playerState,
            onPlayPause: {
                playerService.togglePlayPause()
            },
            onSeek: { time in
                await playerService.seek(to: time)
            },
            onSeekForward: { seconds in
                playerService.seekForward(by: seconds)
            },
            onSeekBackward: { seconds in
                playerService.seekBackward(by: seconds)
            },
            onToggleFullscreen: onToggleFullscreen,
            isFullscreen: isFullscreen,
            isWidescreenVideo: isWidescreenVideo,
            onClose: onClose,
            onTogglePiP: {
                backend.togglePiP()
            },
            onToggleDebug: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    playerState.showDebugOverlay.toggle()
                }
            },
            isWideScreenLayout: isWideScreenLayout,
            onTogglePanel: onTogglePanel,
            isPanelVisible: isPanelVisible,
            panelSide: panelSide,
            onToggleOrientationLock: onToggleOrientationLock,
            isOrientationLocked: isOrientationLocked,
            onToggleDetailsVisibility: onToggleDetailsVisibility,
            onPlayNext: {
                await playerService.playNext()
            },
            onPlayPrevious: {
                await playerService.playPrevious()
            },
            onShowQueue: onShowQueue,
            onVolumeChanged: { [weak appEnvironment] volume in
                playerService.currentBackend?.volume = volume
                appEnvironment?.settingsManager.playerVolume = volume
                appEnvironment?.remoteControlCoordinator.broadcastStateUpdate()
            },
            onMuteToggled: { [weak appEnvironment] in
                let newMuted = !playerState.isMuted
                playerService.currentBackend?.isMuted = newMuted
                playerState.isMuted = newMuted
                appEnvironment?.remoteControlCoordinator.broadcastStateUpdate()
            },
            currentVideo: playerState.currentVideo,
            availableCaptions: playerService.availableCaptions,
            currentCaption: playerService.currentCaption,
            availableStreams: playerService.availableStreams,
            currentStream: playerState.currentStream,
            currentAudioStream: playerState.currentAudioStream,
            onRateChanged: { rate in
                playerState.rate = rate
                playerService.currentBackend?.rate = Float(rate.rawValue)
            },
            onCaptionSelected: { caption in
                playerService.loadCaption(caption)
            },
            onStreamSelected: { stream, audioStream in
                guard let video = playerState.currentVideo else { return }
                let currentTime = playerState.currentTime
                Task {
                    await playerService.play(video: video, stream: stream, audioStream: audioStream, startTime: currentTime)
                }
            }
        )
        #elseif os(macOS)
        MacOSPlayerControlsView(
            playerState: playerState,
            onPlayPause: {
                playerService.togglePlayPause()
            },
            onSeek: { time in
                await playerService.seek(to: time)
            },
            onSeekForward: { seconds in
                playerService.seekForward(by: seconds)
            },
            onSeekBackward: { seconds in
                playerService.seekBackward(by: seconds)
            },
            onToggleFullscreen: onToggleFullscreen,
            isFullscreen: isFullscreen,
            onClose: onClose,
            onPlayNext: {
                await playerService.playNext()
            },
            onVolumeChanged: { [weak appEnvironment] volume in
                playerService.currentBackend?.volume = volume
                appEnvironment?.settingsManager.playerVolume = volume
                appEnvironment?.remoteControlCoordinator.broadcastStateUpdate()
            },
            onMuteToggled: { [weak appEnvironment] in
                let newMuted = !playerState.isMuted
                playerService.currentBackend?.isMuted = newMuted
                playerState.isMuted = newMuted
                appEnvironment?.remoteControlCoordinator.broadcastStateUpdate()
            }
        )
        #else
        // tvOS uses its own player controls (TVPlayerControlsView)
        EmptyView()
        #endif
    }
}

/// Conditionally applies aspect ratio modifier
struct ConditionalAspectRatio: ViewModifier {
    let ratio: Double
    let applies: Bool

    func body(content: Content) -> some View {
        if applies {
            content
                .aspectRatio(ratio, contentMode: .fit)
        } else {
            content
        }
    }
}

// MARK: - Preview

#Preview {
    // Preview requires mock objects
    ZStack {
        Color.black
        Text("MPV Video View")
            .foregroundStyle(.white)
    }
    .aspectRatio(16/9, contentMode: .fit)
}

#endif
