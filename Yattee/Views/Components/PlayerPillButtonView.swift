//
//  PlayerPillButtonView.swift
//  Yattee
//
//  Renders individual buttons within the PlayerPillView.
//  Specialized component with compact sizing and pill-specific behavior.
//  Some buttons render as Menu or ShareLink instead of Button.
//

import SwiftUI

struct PlayerPillButtonView: View {
    let configuration: ControlButtonConfiguration
    let isPlaying: Bool
    let hasNext: Bool
    let queueCount: Int
    let queueModeIcon: String
    let isPlayPauseDisabled: Bool
    let isWideLayout: Bool
    let isOrientationLocked: Bool

    // Context for special buttons
    let video: Video?
    let playbackRate: PlaybackRate
    @Binding var showingPlaylistSheet: Bool

    // Callbacks
    let onAction: () -> Void
    let onRateChanged: (PlaybackRate) -> Void
    let onTogglePiP: () -> Void

    @State private var tapCount = 0

    var body: some View {
        // Some buttons need special SwiftUI components instead of Button
        switch configuration.buttonType {
        case .share:
            shareButton
        case .playbackSpeed:
            playbackSpeedMenu
        case .contextMenu:
            contextMenuButton
        case .addToPlaylist:
            addToPlaylistButton
        case .pictureInPicture:
            pipButton
        case .airplay:
            airplayButton
        default:
            standardButton
        }
    }

    // MARK: - Standard Button (for most button types)

    private var standardButton: some View {
        Button {
            tapCount += 1
            onAction()
        } label: {
            buttonContent
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    @ViewBuilder
    private var buttonContent: some View {
        switch configuration.buttonType {
        case .queue:
            queueButton
        case .playPause:
            playPauseButton
        case .playPrevious:
            transportButton(systemName: "backward.fill", size: 16)
        case .playNext:
            transportButton(systemName: "forward.fill", size: 16, dimmed: !hasNext)
        case .seek:
            seekButton(systemName: seekIcon)
        case .close:
            closeButton
        case .fullscreen:
            fullscreenButton
        case .orientationLock:
            orientationLockButton
        default:
            genericButton
        }
    }

    // MARK: - Queue Button

    private var queueButton: some View {
        ZStack(alignment: .bottom) {
            Image(systemName: queueModeIcon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)

            // Badge showing queue count
            if queueCount > 0 {
                Text("\(queueCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.accentColor, in: Capsule())
                    .offset(x: 0, y: 4)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Play/Pause Button

    private var playPauseButton: some View {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 36)
            .contentShape(Rectangle())
            .contentTransition(.symbolEffect(.replace, options: .speed(2)))
    }

    // MARK: - Transport Buttons (Previous/Next)

    private func transportButton(systemName: String, size: CGFloat, dimmed: Bool = false) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(dimmed ? .tertiary : .primary)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: tapCount)
    }

    // MARK: - Seek Buttons

    private func seekButton(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: tapCount)
    }

    /// SF Symbol name for the seek button based on configured direction and seconds.
    private var seekIcon: String {
        let settings = configuration.seekSettings ?? SeekSettings()
        return settings.systemImage
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Image(systemName: "xmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
    }

    // MARK: - Fullscreen Button

    private var fullscreenButton: some View {
        // Wide layout (landscape) shows portrait rotate icon, and vice versa
        let icon = isWideLayout ? "rectangle.portrait.rotate" : "rectangle.landscape.rotate"
        return Image(systemName: icon)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
    }

    // MARK: - Orientation Lock Button

    private var orientationLockButton: some View {
        let icon = isOrientationLocked ? "lock.rotation" : "lock.rotation.open"
        return Image(systemName: icon)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(isOrientationLocked ? Color.accentColor : .primary)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
    }

    // MARK: - Generic Button (fallback for other types)

    private var genericButton: some View {
        Image(systemName: configuration.buttonType.systemImage)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
    }

    // MARK: - Special Buttons

    #if !os(tvOS)
    private var shareButton: some View {
        Group {
            if let video {
                ShareLink(item: video.shareURL) {
                    genericButtonLabel
                }
                .buttonStyle(.plain)
            } else {
                standardButton
            }
        }
    }
    #else
    private var shareButton: some View {
        standardButton
    }
    #endif

    private var playbackSpeedMenu: some View {
        Menu {
            ForEach(PlaybackRate.allCases) { rate in
                Button {
                    onRateChanged(rate)
                } label: {
                    HStack {
                        Text(rate.displayText)
                        if playbackRate == rate {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            playbackSpeedLabel
        }
        .menuIndicator(.hidden)
        .tint(.primary)
    }

    private var playbackSpeedLabel: some View {
        Text(playbackRate.compactDisplayText)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
    }

    #if !os(tvOS)
    @ViewBuilder
    private var contextMenuButton: some View {
        if let video {
            VideoContextMenuView(video: video, accentColor: .primary)
        } else {
            standardButton
        }
    }
    #else
    private var contextMenuButton: some View {
        standardButton
    }
    #endif

    private var addToPlaylistButton: some View {
        Button {
            showingPlaylistSheet = true
        } label: {
            genericButtonLabel
        }
        .buttonStyle(.plain)
    }

    private var pipButton: some View {
        Button {
            onTogglePiP()
        } label: {
            genericButtonLabel
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var airplayButton: some View {
        #if os(iOS)
        AirPlayButton(tintColor: .label)
            .frame(width: 36, height: 36)
        #elseif os(macOS)
        AirPlayButton()
            .frame(width: 36, height: 36)
        #else
        standardButton
        #endif
    }

    private var genericButtonLabel: some View {
        Image(systemName: configuration.buttonType.systemImage)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
    }

    // MARK: - Disabled State

    private var isDisabled: Bool {
        switch configuration.buttonType {
        case .playPause:
            return isPlayPauseDisabled
        case .playNext:
            return !hasNext
        default:
            return false
        }
    }
}

#Preview("Queue Button") {
    PlayerPillButtonView(
        configuration: ControlButtonConfiguration(buttonType: .queue),
        isPlaying: false,
        hasNext: true,
        queueCount: 5,
        queueModeIcon: "list.bullet",
        isPlayPauseDisabled: false,
        isWideLayout: false,
        isOrientationLocked: false,
        video: nil,
        playbackRate: .x1,
        showingPlaylistSheet: .constant(false),
        onAction: {},
        onRateChanged: { _ in },
        onTogglePiP: {}
    )
    .padding()
    .background(Color.black.opacity(0.8))
}

#Preview("Play/Pause") {
    HStack {
        PlayerPillButtonView(
            configuration: ControlButtonConfiguration(buttonType: .playPause),
            isPlaying: false,
            hasNext: true,
            queueCount: 0,
            queueModeIcon: "list.bullet",
            isPlayPauseDisabled: false,
            isWideLayout: false,
            isOrientationLocked: false,
            video: nil,
            playbackRate: .x1,
            showingPlaylistSheet: .constant(false),
            onAction: {},
            onRateChanged: { _ in },
            onTogglePiP: {}
        )
        PlayerPillButtonView(
            configuration: ControlButtonConfiguration(buttonType: .playPause),
            isPlaying: true,
            hasNext: true,
            queueCount: 0,
            queueModeIcon: "list.bullet",
            isPlayPauseDisabled: false,
            isWideLayout: false,
            isOrientationLocked: false,
            video: nil,
            playbackRate: .x1,
            showingPlaylistSheet: .constant(false),
            onAction: {},
            onRateChanged: { _ in },
            onTogglePiP: {}
        )
    }
    .padding()
    .background(Color.black.opacity(0.8))
}
