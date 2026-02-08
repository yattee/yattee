//
//  MacOSPlayerControlsView.swift
//  Yattee
//
//  QuickTime-style player controls for macOS with hover-to-show behavior and keyboard shortcuts.
//

#if os(macOS)

import AppKit
import SwiftUI

/// QuickTime-style player controls overlay for macOS.
/// Shows condensed control bar on hover, hides when mouse leaves.
struct MacOSPlayerControlsView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Bindable var playerState: PlayerState

    // MARK: - Callbacks

    let onPlayPause: () -> Void
    let onSeek: (TimeInterval) async -> Void
    let onSeekForward: (TimeInterval) async -> Void
    let onSeekBackward: (TimeInterval) async -> Void
    var onToggleFullscreen: (() -> Void)? = nil
    var isFullscreen: Bool = false
    var onClose: (() -> Void)? = nil
    var onTogglePiP: (() -> Void)? = nil
    var onPlayNext: (() async -> Void)? = nil
    var onVolumeChanged: ((Float) -> Void)? = nil
    var onMuteToggled: (() -> Void)? = nil
    var onShowSettings: (() -> Void)? = nil

    // MARK: - State

    @State private var isHovering = false
    @State private var hideTimer: Timer?
    @State private var isInteracting = false
    @State private var showControls: Bool?
    @State private var keyboardMonitor: Any?

    // MARK: - Computed Properties

    /// Controls visibility - show when hovering, interacting, or paused
    private var shouldShowControls: Bool {
        if let showControls {
            return showControls
        }
        // Show if hovering, interacting (scrubbing, adjusting volume), or paused
        if isHovering || isInteracting {
            return true
        }
        // Show when paused, loading, or failed
        return playerState.playbackState == .paused ||
               playerState.playbackState == .loading ||
               playerState.playbackState == .ended ||
               playerState.isFailed
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Invisible layer for tap/click to toggle controls
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleControlsVisibility()
                    }
                    .allowsHitTesting(playerState.playbackState != .ended && !playerState.isFailed)

                // Control bar at bottom center
                VStack {
                    Spacer()

                    MacOSControlBar(
                        playerState: playerState,
                        onPlayPause: {
                            let wasPaused = playerState.playbackState == .paused
                            onPlayPause()
                            showControls = true
                            if wasPaused {
                                resetHideTimer()
                            }
                        },
                        onSeek: onSeek,
                        onSeekForward: onSeekForward,
                        onSeekBackward: onSeekBackward,
                        onToggleFullscreen: onToggleFullscreen,
                        isFullscreen: isFullscreen,
                        onTogglePiP: onTogglePiP,
                        onPlayNext: onPlayNext,
                        onVolumeChanged: onVolumeChanged,
                        onMuteToggled: onMuteToggled,
                        onShowSettings: onShowSettings,
                        sponsorSegments: playerState.sponsorSegments,
                        onInteractionStarted: {
                            isInteracting = true
                            cancelHideTimer()
                        },
                        onInteractionEnded: {
                            isInteracting = false
                            resetHideTimer()
                        }
                    )
                    .frame(width: 650)
                }
                .padding(.bottom, 20)
                .opacity(shouldShowControls ? 1 : 0)
                .allowsHitTesting(shouldShowControls)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .animation(.easeInOut(duration: 0.2), value: shouldShowControls)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHovering = true
                resetHideTimer()
            case .ended:
                isHovering = false
                startHideTimer()
            }
        }
        .onChange(of: playerState.playbackState) { oldState, newState in
            // When playback starts, start hide timer
            if newState == .playing && shouldShowControls {
                startHideTimer()
            }
            // Hide controls when video ends (ended overlay takes over)
            if newState == .ended {
                showControls = false
                cancelHideTimer()
            }
            // Hide controls when video fails
            if case .failed = newState {
                showControls = false
                cancelHideTimer()
            }
        }
        .onAppear {
            setupKeyboardMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
    }

    // MARK: - Keyboard Shortcuts

    private func setupKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Only handle events when the player window is key (active)
            guard NSApp.keyWindow != nil else { return event }

            // Handle keyboard shortcuts
            switch event.keyCode {
            case 49: // Space
                onPlayPause()
                return nil // Consume event

            case 123: // Left arrow
                Task { await onSeek(max(0, playerState.currentTime - 5)) }
                return nil

            case 124: // Right arrow
                Task { await onSeek(min(playerState.duration, playerState.currentTime + 5)) }
                return nil

            case 126: // Up arrow
                let newVolume = min(1.0, playerState.volume + 0.1)
                playerState.volume = newVolume
                onVolumeChanged?(newVolume)
                return nil

            case 125: // Down arrow
                let newVolume = max(0, playerState.volume - 0.1)
                playerState.volume = newVolume
                onVolumeChanged?(newVolume)
                return nil

            case 46: // M key
                onMuteToggled?()
                return nil

            case 3: // F key
                onToggleFullscreen?()
                return nil

            case 53: // Escape
                if isFullscreen {
                    onToggleFullscreen?()
                    return nil
                }
                return event // Pass through if not fullscreen

            default:
                return event // Pass through unhandled keys
            }
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }

    // MARK: - Timer Management

    private func toggleControlsVisibility() {
        showControls = !shouldShowControls
        if shouldShowControls {
            startHideTimer()
        }
    }

    private func startHideTimer() {
        cancelHideTimer()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            Task { @MainActor in
                if playerState.playbackState == .playing && !isInteracting && !isHovering {
                    showControls = false
                }
            }
        }
    }

    private func resetHideTimer() {
        startHideTimer()
    }

    private func cancelHideTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black

        MacOSPlayerControlsView(
            playerState: PlayerState(),
            onPlayPause: {},
            onSeek: { _ in },
            onSeekForward: { _ in },
            onSeekBackward: { _ in }
        )
    }
    .aspectRatio(16/9, contentMode: .fit)
    .frame(width: 800, height: 450)
}

#endif
