//
//  TVPlayerControlsView.swift
//  Yattee
//
//  AVKit-style player controls overlay for tvOS with focus-based navigation.
//

#if os(tvOS)
import SwiftUI

/// AVKit-style player controls overlay for tvOS.
struct TVPlayerControlsView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    let playerState: PlayerState?
    let playerService: PlayerService?
    @FocusState.Binding var focusedControl: TVPlayerFocusTarget?

    let onShowDetails: () -> Void
    let onShowQuality: () -> Void
    let onShowDebug: () -> Void
    let onDismiss: () -> Void
    /// Called when scrubbing state changes - parent should stop auto-hide timer when true
    var onScrubbingChanged: ((Bool) -> Void)?

    /// Whether to show in-app volume controls (only when volume mode is .mpv)
    private var showVolumeControls: Bool {
        GlobalLayoutSettings.cached.volumeMode == .mpv
    }

    @State private var playNextTapCount = 0
    @State private var seekBackwardTrigger = 0
    @State private var seekForwardTrigger = 0

    var body: some View {
        ZStack {
            // Gradient overlay for readability
            gradientOverlay

            VStack(spacing: 0) {
                // Top bar with title and channel
                topBar
                    .padding(.top, 60)
                    .padding(.horizontal, 88)

                Spacer()

                // Center transport controls - focus section for horizontal nav
                transportControls
                    .focusSection()
                    // DEBUG: Uncomment to see focus section boundaries
                    // .border(.blue, width: 2)

                Spacer()

                // Progress bar - its own focus section
                TVPlayerProgressBar(
                    currentTime: playerState?.currentTime ?? 0,
                    duration: playerState?.duration ?? 0,
                    bufferedTime: playerState?.bufferedTime ?? 0,
                    storyboard: playerState?.preferredStoryboard,
                    chapters: playerState?.chapters ?? [],
                    onSeek: { time in
                        Task {
                            await playerService?.seek(to: time)
                        }
                    },
                    onScrubbingChanged: onScrubbingChanged,
                    isLive: playerState?.isLive ?? false,
                    sponsorSegments: playerState?.sponsorSegments ?? []
                )
                .focusSection()
                .padding(.horizontal, 88)
                .padding(.bottom, 20)
                // DEBUG: Uncomment to see focus section boundaries
                // .border(.green, width: 2)

                // Action buttons row - focus section for horizontal nav
                actionButtons
                    .focusSection()
                    .padding(.horizontal, 88)
                    .padding(.bottom, 60)
                    // DEBUG: Uncomment to see focus section boundaries
                    // .border(.red, width: 2)
            }
        }
    }

    // MARK: - Gradient Overlay

    private var gradientOverlay: some View {
        VStack(spacing: 0) {
            // Top gradient
            LinearGradient(
                colors: [.black.opacity(0.8), .black.opacity(0.4), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)

            Spacer()

            // Bottom gradient
            LinearGradient(
                colors: [.clear, .black.opacity(0.4), .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 300)
        }
        .ignoresSafeArea()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                // Video title
                Text(playerState?.currentVideo?.title ?? "")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .foregroundStyle(.white)

                // Channel name
                if let channelName = playerState?.currentVideo?.author.name {
                    Text(channelName)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Spacer()

            // Loading indicator
            if playerState?.playbackState == .loading || playerState?.playbackState == .buffering {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
            }
        }
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: 80) {
            // Skip backward
            Button {
                seekBackwardTrigger += 1
                playerService?.seekBackward(by: 10)
            } label: {
                Image(systemName: "10.arrow.trianglehead.counterclockwise")
                    .font(.system(size: 52, weight: .medium))
                    .symbolEffect(.rotate.byLayer, options: .speed(2).nonRepeating, value: seekBackwardTrigger)
            }
            .buttonStyle(TVTransportButtonStyle())
            .focused($focusedControl, equals: .skipBackward)
            .disabled(isTransportDisabled)

            // Play/Pause - hide when transport disabled, show spacer to maintain layout
            if !isTransportDisabled {
                Button {
                    playerService?.togglePlayPause()
                } label: {
                    Image(systemName: playPauseIcon)
                        .font(.system(size: 72, weight: .medium))
                        .contentTransition(.symbolEffect(.replace, options: .speed(2)))
                }
                .buttonStyle(TVTransportButtonStyle())
                .focused($focusedControl, equals: .playPause)
            } else {
                // Invisible spacer maintains layout stability
                Color.clear
                    .frame(width: 72, height: 72)
                    .allowsHitTesting(false)
            }

            // Skip forward
            Button {
                seekForwardTrigger += 1
                playerService?.seekForward(by: 10)
            } label: {
                Image(systemName: "10.arrow.trianglehead.clockwise")
                    .font(.system(size: 52, weight: .medium))
                    .symbolEffect(.rotate.byLayer, options: .speed(2).nonRepeating, value: seekForwardTrigger)
            }
            .buttonStyle(TVTransportButtonStyle())
            .focused($focusedControl, equals: .skipForward)
            .disabled(isTransportDisabled)
        }
    }

    /// Whether transport controls should be disabled (during loading/buffering or buffer not ready)
    private var isTransportDisabled: Bool {
        playerState?.playbackState == .loading ||
        playerState?.playbackState == .buffering ||
        !(playerState?.isFirstFrameReady ?? false) ||
        !(playerState?.isBufferReady ?? false)
    }

    private var playPauseIcon: String {
        switch playerState?.playbackState {
        case .playing:
            return "pause.fill"
        default:
            return "play.fill"
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 40) {
            // Quality selector
            Button {
                onShowQuality()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 28))
                    Text("player.controls.quality")
                        .font(.caption)
                }
            }
            .buttonStyle(TVActionButtonStyle())
            .focused($focusedControl, equals: .qualityButton)

            // Captions
            Button {
                // TODO: Show captions picker
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "captions.bubble")
                        .font(.system(size: 28))
                    Text(String(localized: "player.controls.subtitles"))
                        .font(.caption)
                }
            }
            .buttonStyle(TVActionButtonStyle())
            .focused($focusedControl, equals: .captionsButton)

            // Debug overlay
            Button {
                onShowDebug()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "ant.circle")
                        .font(.system(size: 28))
                    Text(String(localized: "player.debug.titleShort"))
                        .font(.caption)
                }
            }
            .buttonStyle(TVActionButtonStyle())
            .focused($focusedControl, equals: .debugButton)

            // Info / Details
            Button {
                onShowDetails()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 28))
                    Text("player.controls.info")
                        .font(.caption)
                }
            }
            .buttonStyle(TVActionButtonStyle())
            .focused($focusedControl, equals: .infoButton)

            // Volume controls (only when in-app volume mode)
            if showVolumeControls {
                // Volume down
                Button {
                    guard let state = playerState else { return }
                    let newVolume = max(0, state.volume - 0.1)
                    playerService?.currentBackend?.volume = newVolume
                    playerService?.state.volume = newVolume
                    appEnvironment?.settingsManager.playerVolume = newVolume
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "speaker.minus")
                            .font(.system(size: 28))
                        Text(String(localized: "player.tvos.volumeDown"))
                            .font(.caption)
                    }
                }
                .buttonStyle(TVActionButtonStyle())
                .focused($focusedControl, equals: .volumeDown)

                // Volume up
                Button {
                    guard let state = playerState else { return }
                    let newVolume = min(1.0, state.volume + 0.1)
                    playerService?.currentBackend?.volume = newVolume
                    playerService?.state.volume = newVolume
                    appEnvironment?.settingsManager.playerVolume = newVolume
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "speaker.plus")
                            .font(.system(size: 28))
                        Text(String(localized: "player.tvos.volumeUp"))
                            .font(.caption)
                    }
                }
                .buttonStyle(TVActionButtonStyle())
                .focused($focusedControl, equals: .volumeUp)
            }

            // Play next button (when queue has items)
            if let state = playerState, state.hasNext {
                Button {
                    playNextTapCount += 1
                    Task { await playerService?.playNext() }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 28))
                            .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: playNextTapCount)
                        Text(String(localized: "player.next"))
                            .font(.caption)
                    }
                }
                .buttonStyle(TVActionButtonStyle())
                .focused($focusedControl, equals: .playNext)
            }

            Spacer()

            // Queue indicator (if videos in queue)
            if let state = playerState, state.hasNext {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 20))
                    Text(String(localized: "queue.section.count \(state.queue.count)"))
                        .font(.subheadline)
                }
                .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Button Styles

/// Button style for transport controls (play/pause, skip).
struct TVTransportButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.9 : (isFocused ? 1.15 : 1.0))
            .shadow(color: isFocused ? .white.opacity(0.5) : .clear, radius: 20)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Button style for action buttons (quality, captions, info).
struct TVActionButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(width: 100, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? .white.opacity(0.3) : .white.opacity(0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.05 : 1.0))
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#endif
