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

    let onShowSettings: () -> Void
    let onShowQueue: () -> Void
    let onShowDetails: () -> Void
    let onShowComments: () -> Void
    let onShowDebug: () -> Void
    let onClose: () -> Void
    /// Called when scrubbing state changes - parent should stop auto-hide timer when true
    var onScrubbingChanged: ((Bool) -> Void)?
    /// Pending target time for the bar's accumulating remote-seek flow (arrow
    /// presses while focused but not in SELECT scrub mode).
    var remoteSeekTime: TimeInterval? = nil
    /// Called when user presses left/right on the focused bar outside SELECT scrub.
    var onRemoteSeek: ((Bool) -> Void)? = nil
    /// Bumped by the parent to cancel any in-progress scrub without seeking
    /// (used when the Menu button is pressed while scrubbing).
    var cancelScrubTrigger: UUID? = nil

    /// Whether the Debug button should be visible (user-toggled in Developer settings).
    private var showDebugButton: Bool {
        appEnvironment?.settingsManager.showTVDebugButton ?? false
    }

    @State private var playNextTapCount = 0
    @State private var playPreviousTapCount = 0
    @State private var playPauseTapCount = 0

    private var isPlaying: Bool {
        playerState?.playbackState == .playing
    }

    private var isTransportDisabled: Bool {
        playerState?.isTransportDisabled ?? true
    }

    private var playPauseIcon: String {
        isPlaying ? "pause.fill" : "play.fill"
    }

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
                    sponsorSegments: playerState?.sponsorSegments ?? [],
                    remoteSeekTime: remoteSeekTime,
                    onRemoteSeek: onRemoteSeek,
                    cancelScrubTrigger: cancelScrubTrigger
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
        HStack(alignment: .center, spacing: 20) {
            // Channel avatar
            if let video = playerState?.currentVideo {
                ChannelAvatarView(
                    author: video.author,
                    size: 80,
                    yatteeServerURL: yatteeServerURL,
                    source: video.id.source
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                // Video title
                Text(playerState?.currentVideo?.title ?? "")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .foregroundStyle(.white)

                // Channel name
                if let channelName = playerState?.currentVideo?.author.name {
                    Text(channelName)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Spacer()

            // Loading indicator
            if playerState?.playbackState == .loading || playerState?.playbackState == .buffering {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
                    .padding(.trailing, 8)
            }

            // Close button — stops playback and dismisses.
            // Menu button only hides the player (keeps background playback),
            // so an explicit Close is kept here, icon-only in the top bar.
            // When `tvOSMenuButtonClosesVideo` is enabled, the Menu button
            // takes over this role and the explicit button is hidden.
            if appEnvironment?.settingsManager.tvOSMenuButtonClosesVideo != true {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 26, weight: .semibold))
                }
                .buttonStyle(TVCloseButtonStyle())
                .focused($focusedControl, equals: .closeButton)
                .accessibilityLabel(Text("player.controls.close"))
            }
        }
    }

    private var yatteeServerURL: URL? {
        appEnvironment?.instancesManager.yatteeServerInstances.first { $0.isEnabled }?.url
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 24) {
            // MARK: Left cluster — info / meta actions
            HStack(spacing: 24) {
                Button {
                    onShowSettings()
                } label: {
                    TVActionButtonLabel(
                        systemImage: "gearshape",
                        title: String(localized: "player.controls.settings")
                    )
                }
                .buttonStyle(TVActionButtonStyle())
                .focused($focusedControl, equals: .settingsButton)

                Button {
                    onShowDetails()
                } label: {
                    TVActionButtonLabel(
                        systemImage: "info.circle",
                        title: String(localized: "player.controls.info")
                    )
                }
                .buttonStyle(TVActionButtonStyle())
                .focused($focusedControl, equals: .infoButton)

                if playerState?.currentVideo?.supportsComments == true {
                    Button {
                        onShowComments()
                    } label: {
                        TVActionButtonLabel(
                            systemImage: "bubble.left.and.bubble.right",
                            title: String(localized: "player.controls.comments")
                        )
                    }
                    .buttonStyle(TVActionButtonStyle())
                    .focused($focusedControl, equals: .commentsButton)
                }

                if showDebugButton {
                    Button {
                        onShowDebug()
                    } label: {
                        TVActionButtonLabel(
                            systemImage: "ant.circle",
                            title: String(localized: "player.debug.titleShort")
                        )
                    }
                    .buttonStyle(TVActionButtonStyle())
                    .focused($focusedControl, equals: .debugButton)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // MARK: Center cluster — transport (circular, icon-only)
            HStack(spacing: 20) {
                // Previous is always rendered so Play/Next stay in a fixed
                // position; disabled + dimmed when unavailable.
                let hasPrevious = playerState?.hasPrevious == true
                Button {
                    playPreviousTapCount += 1
                    Task { await playerService?.playPrevious() }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: playPreviousTapCount)
                }
                .buttonStyle(TVTransportButtonStyle())
                .focused($focusedControl, equals: .playPrevious)
                .disabled(!hasPrevious)
                .opacity(hasPrevious ? 1.0 : 0.3)
                .accessibilityLabel(Text("player.previous"))

                Button {
                    playPauseTapCount += 1
                    playerService?.togglePlayPause()
                } label: {
                    Image(systemName: playPauseIcon)
                        .font(.system(size: 32, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace, options: .speed(2)))
                        .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: playPauseTapCount)
                }
                .buttonStyle(TVTransportButtonStyle(isPrimary: true))
                .focused($focusedControl, equals: .playPauseButton)
                .disabled(isTransportDisabled)
                .opacity(isTransportDisabled ? 0.3 : 1.0)
                .accessibilityLabel(Text(isPlaying ? "player.controls.pause" : "player.controls.play"))

                let hasNext = playerState?.hasNext == true
                Button {
                    playNextTapCount += 1
                    Task { await playerService?.playNext() }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: playNextTapCount)
                }
                .buttonStyle(TVTransportButtonStyle())
                .focused($focusedControl, equals: .playNext)
                .disabled(!hasNext)
                .opacity(hasNext ? 1.0 : 0.3)
                .accessibilityLabel(Text("player.next"))
            }

            // MARK: Right cluster — queue
            HStack(spacing: 24) {
                Spacer(minLength: 0)

                if let state = playerState, state.hasNext {
                    Button {
                        onShowQueue()
                    } label: {
                        TVActionButtonLabel(
                            systemImage: "list.bullet",
                            title: String(localized: "queue.section.count \(state.queue.count)")
                        )
                    }
                    .buttonStyle(TVActionButtonStyle())
                    .focused($focusedControl, equals: .queueButton)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - Button Label

/// Shared label for action buttons: icon always visible, title only on focus.
private struct TVActionButtonLabel: View {
    let systemImage: String
    let title: String
    var symbolEffectTrigger: Int = 0

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: symbolEffectTrigger)
            Text(title)
                .font(.caption)
        }
    }
}

// MARK: - Button Styles

/// Button style for action buttons (settings, info, transport, queue).
/// Width is adaptive so localized labels fit when revealed on focus.
struct TVActionButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 20)
            .frame(minWidth: 100, minHeight: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? .white.opacity(0.3) : .white.opacity(0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.05 : 1.0))
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Circular icon-only button style for transport controls (previous / play-pause / next).
/// Primary variant is larger and uses a filled white background when focused.
struct TVTransportButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    var isPrimary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let size: CGFloat = isPrimary ? 88 : 72
        return configuration.label
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(isFocused
                        ? (isPrimary ? .white.opacity(0.95) : .white.opacity(0.3))
                        : (isPrimary ? .white.opacity(0.25) : .white.opacity(0.12)))
            )
            .foregroundStyle(isFocused && isPrimary ? Color.black : .white)
            .scaleEffect(configuration.isPressed ? 0.92 : (isFocused ? 1.08 : 1.0))
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Compact circular button style for the top-right close affordance.
struct TVCloseButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(
                Circle()
                    .fill(isFocused ? .white.opacity(0.3) : .white.opacity(0.12))
            )
            .scaleEffect(configuration.isPressed ? 0.92 : (isFocused ? 1.08 : 1.0))
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#endif
