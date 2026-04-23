//
//  PlayerPillView.swift
//  Yattee
//
//  A rounded pill showing customizable player controls.
//  Supports dynamic buttons and horizontal scroll when space is limited.
//

import SwiftUI

// MARK: - Content Width Preference Key

private struct ContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct PlayerPillView: View {
    let settings: PlayerPillSettings
    let maxWidth: CGFloat?
    let isWideLayout: Bool
    let isPlaying: Bool
    let hasNext: Bool
    let queueCount: Int
    let queueModeIcon: String
    let isPlayPauseDisabled: Bool
    let isOrientationLocked: Bool

    // Video context for special buttons
    let video: Video?
    let playbackRate: PlaybackRate
    @Binding var showingPlaylistSheet: Bool

    // Action callbacks
    let onQueueTap: () -> Void
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    /// Callback for seek actions. Positive seconds = forward, negative = backward.
    let onSeek: ((TimeInterval) async -> Void)?
    let onClose: () -> Void
    let onAirPlay: () -> Void
    let onPiP: () -> Void
    let onOrientationLock: () -> Void
    let onFullscreen: () -> Void
    let onRateChanged: (PlaybackRate) -> Void

    // Measured content width for hug-content behavior
    @State private var contentWidth: CGFloat = 0

    init(
        settings: PlayerPillSettings,
        maxWidth: CGFloat? = nil,
        isWideLayout: Bool = false,
        isPlaying: Bool,
        hasNext: Bool,
        queueCount: Int = 0,
        queueModeIcon: String = "list.bullet",
        isPlayPauseDisabled: Bool = false,
        isOrientationLocked: Bool = false,
        video: Video? = nil,
        playbackRate: PlaybackRate = .x1,
        showingPlaylistSheet: Binding<Bool> = .constant(false),
        onQueueTap: @escaping () -> Void = {},
        onPrevious: @escaping () -> Void = {},
        onPlayPause: @escaping () -> Void = {},
        onNext: @escaping () -> Void = {},
        onSeek: ((TimeInterval) async -> Void)? = nil,
        onClose: @escaping () -> Void = {},
        onAirPlay: @escaping () -> Void = {},
        onPiP: @escaping () -> Void = {},
        onOrientationLock: @escaping () -> Void = {},
        onFullscreen: @escaping () -> Void = {},
        onRateChanged: @escaping (PlaybackRate) -> Void = { _ in }
    ) {
        self.settings = settings
        self.maxWidth = maxWidth
        self.isWideLayout = isWideLayout
        self.isPlaying = isPlaying
        self.hasNext = hasNext
        self.queueCount = queueCount
        self.queueModeIcon = queueModeIcon
        self.isPlayPauseDisabled = isPlayPauseDisabled
        self.isOrientationLocked = isOrientationLocked
        self.video = video
        self.playbackRate = playbackRate
        self._showingPlaylistSheet = showingPlaylistSheet
        self.onQueueTap = onQueueTap
        self.onPrevious = onPrevious
        self.onPlayPause = onPlayPause
        self.onNext = onNext
        self.onSeek = onSeek
        self.onClose = onClose
        self.onAirPlay = onAirPlay
        self.onPiP = onPiP
        self.onOrientationLock = onOrientationLock
        self.onFullscreen = onFullscreen
        self.onRateChanged = onRateChanged
    }

    var body: some View {
        // Hide pill if no buttons configured
        if settings.buttons.isEmpty {
            EmptyView()
        } else {
            pillContent
        }
    }

    // MARK: - Pill Content

    /// Calculates the width for the pill based on content and max constraints
    private var pillWidth: CGFloat? {
        guard contentWidth > 0 else { return nil }  // Wait for measurement
        if let maxWidth {
            return min(contentWidth, maxWidth)
        }
        return contentWidth  // No max, use content width
    }

    /// True when all buttons fit in available width; scrolling should be disabled.
    private var contentFitsInAvailableWidth: Bool {
        guard let maxWidth else { return true }
        guard contentWidth > 0 else { return false }
        return contentWidth <= maxWidth
    }

    private var pillContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(settings.buttons) { config in
                    PlayerPillButtonView(
                        configuration: config,
                        isPlaying: isPlaying,
                        hasNext: hasNext,
                        queueCount: queueCount,
                        queueModeIcon: queueModeIcon,
                        isPlayPauseDisabled: isPlayPauseDisabled,
                        isWideLayout: isWideLayout,
                        isOrientationLocked: isOrientationLocked,
                        video: video,
                        playbackRate: playbackRate,
                        showingPlaylistSheet: $showingPlaylistSheet,
                        onAction: { handleAction(for: config) },
                        onRateChanged: onRateChanged,
                        onTogglePiP: onPiP
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ContentWidthKey.self, value: geo.size.width)
                }
            )
        }
        .onPreferenceChange(ContentWidthKey.self) { contentWidth = $0 }
        .scrollDisabled(contentFitsInAvailableWidth)
        .frame(width: pillWidth)
        .scrollBounceBehavior(.basedOnSize)
        .fixedSize(horizontal: false, vertical: true)  // Pill sizes to content height
        .glassBackground(.regular, in: .capsule, fallback: .thinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
    }

    // MARK: - Action Routing

    private func handleAction(for config: ControlButtonConfiguration) {
        switch config.buttonType {
        case .queue:
            onQueueTap()
        case .playPrevious:
            onPrevious()
        case .playPause:
            onPlayPause()
        case .playNext:
            onNext()
        case .seek:
            let settings = config.seekSettings ?? SeekSettings()
            // Pass signed seconds: positive for forward, negative for backward
            let signedSeconds = settings.direction == .forward ? TimeInterval(settings.seconds) : -TimeInterval(settings.seconds)
            Task {
                await onSeek?(signedSeconds)
            }
        case .close:
            onClose()
        case .airplay:
            onAirPlay()
        case .orientationLock:
            onOrientationLock()
        case .fullscreen:
            onFullscreen()
        // These are handled directly by PlayerPillButtonView:
        // .share, .playbackSpeed, .contextMenu, .addToPlaylist, .pictureInPicture
        default:
            break
        }
    }
}

// MARK: - Previews

#Preview("Playing") {
    ZStack {
        Color.black.opacity(0.8)
        PlayerPillView(
            settings: .default,
            isPlaying: true,
            hasNext: true,
            queueCount: 5
        )
    }
}

#Preview("Paused") {
    ZStack {
        Color.black.opacity(0.8)
        PlayerPillView(
            settings: .default,
            isPlaying: false,
            hasNext: true,
            queueCount: 5
        )
    }
}

#Preview("Many Buttons") {
    ZStack {
        Color.black.opacity(0.8)
        PlayerPillView(
            settings: PlayerPillSettings(
                visibility: .both,
                buttons: [
                    ControlButtonConfiguration(buttonType: .queue),
                    ControlButtonConfiguration(buttonType: .playPrevious),
                    ControlButtonConfiguration(buttonType: .playPause),
                    ControlButtonConfiguration(buttonType: .playNext),
                    ControlButtonConfiguration(
                        buttonType: .seek,
                        settings: .seek(SeekSettings(seconds: 10, direction: .backward))
                    ),
                    ControlButtonConfiguration(
                        buttonType: .seek,
                        settings: .seek(SeekSettings(seconds: 10, direction: .forward))
                    ),
                    ControlButtonConfiguration(buttonType: .airplay),
                    ControlButtonConfiguration(buttonType: .pictureInPicture),
                    ControlButtonConfiguration(buttonType: .close)
                ]
            ),
            maxWidth: 300,
            isPlaying: true,
            hasNext: true,
            queueCount: 3
        )
    }
}
