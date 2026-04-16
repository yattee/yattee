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
            }
        }
    }

    private var yatteeServerURL: URL? {
        appEnvironment?.instancesManager.yatteeServerInstances.first { $0.isEnabled }?.url
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 40) {
            // Settings (video / audio / subtitles / speed)
            Button {
                onShowSettings()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 28))
                    Text("player.controls.settings")
                        .font(.caption)
                }
            }
            .buttonStyle(TVActionButtonStyle())
            .focused($focusedControl, equals: .settingsButton)

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

            // Comments (opens details panel on Comments tab)
            if playerState?.currentVideo?.supportsComments == true {
                Button {
                    onShowComments()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 28))
                        Text("player.controls.comments")
                            .font(.caption)
                    }
                }
                .buttonStyle(TVActionButtonStyle())
                .focused($focusedControl, equals: .commentsButton)
            }

            // Debug overlay (only when enabled in Developer settings)
            if showDebugButton {
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
            }

            // Play previous button (shown whenever a queue is present; disabled when no history)
            if let state = playerState, state.hasNext || state.hasPrevious {
                Button {
                    playPreviousTapCount += 1
                    Task { await playerService?.playPrevious() }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 28))
                            .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: playPreviousTapCount)
                        Text(String(localized: "player.previous"))
                            .font(.caption)
                    }
                }
                .buttonStyle(TVActionButtonStyle())
                .focused($focusedControl, equals: .playPrevious)
                .disabled(!state.hasPrevious)
                .opacity(state.hasPrevious ? 1.0 : 0.4)
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

            // Queue button (if videos in queue)
            if let state = playerState, state.hasNext {
                Button {
                    onShowQueue()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 28))
                        Text(String(localized: "queue.section.count \(state.queue.count)"))
                            .font(.caption)
                    }
                }
                .buttonStyle(TVActionButtonStyle())
                .focused($focusedControl, equals: .queueButton)
            }

            // Close (stops playback and dismisses)
            Button {
                onClose()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 28))
                    Text("player.controls.close")
                        .font(.caption)
                }
            }
            .buttonStyle(TVActionButtonStyle())
            .focused($focusedControl, equals: .closeButton)
        }
    }
}

// MARK: - Button Styles

/// Button style for action buttons (quality, captions, info).
struct TVActionButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 140, height: 80)
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
