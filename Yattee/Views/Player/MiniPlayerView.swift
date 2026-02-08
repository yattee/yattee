//
//  MiniPlayerView.swift
//  Yattee
//
//  Mini player bar shown at bottom of screen during playback.
//

import SwiftUI
import NukeUI

#if os(iOS) || os(macOS)
struct MiniPlayerView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    /// Whether this is displayed as a tab bottom accessory (affects styling)
    var isTabAccessory: Bool = false

    @State private var buttonTapCounts: [UUID: Int] = [:]
    @State private var miniPlayerSettings: MiniPlayerSettings = MiniPlayerSettings.cached

    private var playerService: PlayerService? { appEnvironment?.playerService }
    private var playerState: PlayerState? { playerService?.state }
    private var navigationCoordinator: NavigationCoordinator? { appEnvironment?.navigationCoordinator }
    private var deArrowProvider: DeArrowBrandingProvider? { appEnvironment?.deArrowBrandingProvider }
    private var queueManager: QueueManager? { appEnvironment?.queueManager }
    private var playerControlsLayoutService: PlayerControlsLayoutService? { appEnvironment?.playerControlsLayoutService }
    private var settingsManager: SettingsManager? { appEnvironment?.settingsManager }

    private var currentVideo: Video? { playerState?.currentVideo }

    /// Whether video preview should be shown (video ready and player not expanded/expanding)
    private var shouldShowVideoPreview: Bool {
        guard let state = playerState else { return false }
        guard let nav = navigationCoordinator else { return false }
        // Check if video preview is enabled in settings
        guard miniPlayerSettings.showVideo else { return false }
        // Don't show video preview for audio-only streams - keep thumbnail visible
        let isAudioOnly = state.currentStream?.isAudioOnly == true
        guard !isAudioOnly else { return false }
        let isVideoReady = state.isFirstFrameReady && state.isBufferReady
        // Don't show video preview when player is expanded or expanding (but OK during collapse)
        // This prevents stealing the MPV player view from the expanded player during expand
        let isPlayerActive = nav.isPlayerExpanded || nav.isPlayerExpanding
        return isVideoReady && !isPlayerActive
    }

    /// Whether we should include the MPVRenderView in the hierarchy (even if hidden)
    /// During collapse, we want the view mounted so it can receive the player view immediately
    private var shouldMountVideoView: Bool {
        guard playerService?.currentBackend is MPVBackend else { return false }
        guard let nav = navigationCoordinator else { return false }
        // Don't mount video view if setting is disabled
        guard miniPlayerSettings.showVideo else { return false }
        // Mount when: not expanding AND (collapsing OR should show preview)
        // This ensures the container exists during collapse to receive the player view
        return !nav.isPlayerExpanding && (nav.isPlayerCollapsing || shouldShowVideoPreview)
    }

    /// The title to display, preferring DeArrow title if available.
    private var displayTitle: String {
        if let video = currentVideo, let deArrowTitle = deArrowProvider?.title(for: video) {
            return deArrowTitle
        }
        return currentVideo?.title ?? String(localized: "player.notPlaying")
    }

    /// The thumbnail URL to display, preferring DeArrow thumbnail if available.
    private var displayThumbnailURL: URL? {
        if let video = currentVideo, let deArrowThumbnail = deArrowProvider?.thumbnailURL(for: video) {
            return deArrowThumbnail
        }
        return currentVideo?.bestThumbnail?.url
    }

    // MARK: - Actions

    /// Handle tap on video preview - action based on settings (PiP or expand)
    /// When video is disabled, always expand player since PiP needs the video view mounted
    private func handleVideoPreviewTap() {
        // If video is disabled in mini player, always expand (can't start PiP without video view)
        guard miniPlayerSettings.showVideo else {
            navigationCoordinator?.expandPlayer()
            return
        }

        switch miniPlayerSettings.videoTapAction {
        case .startPiP:
            if let backend = playerService?.currentBackend as? MPVBackend {
                backend.startPiP()
            } else {
                navigationCoordinator?.expandPlayer()
            }
        case .expandPlayer:
            navigationCoordinator?.expandPlayer()
        }
    }

    /// Expand player, restoring from PiP first if needed
    /// If PiP is active, stops PiP and waits for it to close before expanding
    private func expandPlayerWithPiPRestore() {
        if let backend = playerService?.currentBackend as? MPVBackend, backend.isPiPActive {
            // Stop PiP first, wait for it to close, then expand
            backend.stopPiP()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                navigationCoordinator?.expandPlayer()
            }
        } else {
            navigationCoordinator?.expandPlayer()
        }
    }

    var body: some View {
        Group {
            if isTabAccessory {
                accessoryLayout
            } else {
                overlayLayout
            }
        }
        .accessibilityIdentifier("player.miniPlayer")
        .accessibilityLabel("player.miniPlayer")
        .modifier(MiniPlayerContextMenuModifier(video: currentVideo) {
            queueManager?.clearQueue()
            playerService?.stop()
        })
        .task {
            await loadMiniPlayerSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .playerControlsActivePresetDidChange)) { _ in
            Task { await loadMiniPlayerSettings() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .playerControlsPresetsDidChange)) { _ in
            Task { await loadMiniPlayerSettings() }
        }
    }

    /// Loads mini player settings from the active preset.
    private func loadMiniPlayerSettings() async {
        guard let layoutService = playerControlsLayoutService else { return }
        let layout = await layoutService.activeLayout()
        await MainActor.run {
            miniPlayerSettings = layout.effectiveMiniPlayerSettings
            MiniPlayerSettings.cached = layout.effectiveMiniPlayerSettings
            GlobalLayoutSettings.cached = layout.globalSettings
        }
    }

    // MARK: - Tab Accessory Layout (iOS 26+)

    private var accessoryLayout: some View {
        HStack(spacing: 8) {
            // Video preview - tap for PiP (or expand if PiP unavailable)
            videoPreviewView
                .frame(width: 64, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture {
                    handleVideoPreviewTap()
                }

            // Title/author - tap to expand player (restores from PiP first if needed)
            Button {
                expandPlayerWithPiPRestore()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(
                        text: displayTitle,
                        font: .subheadline,
                        fontWeight: .medium,
                        foregroundStyle: .primary
                    )

                    if let authorName = currentVideo?.author.name, !authorName.isEmpty {
                        MarqueeText(
                            text: authorName,
                            font: .caption,
                            foregroundStyle: .secondary
                        )
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Dynamic buttons from settings
            buttonsView
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
    }

    // MARK: - Overlay Layout

    private var overlayLayout: some View {
        HStack(spacing: 12) {
            // Video preview - tap for PiP (or expand if PiP unavailable)
            videoPreviewView
                .frame(width: 60, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .onTapGesture {
                    handleVideoPreviewTap()
                }

            // Title/author area - tap to expand player (restores from PiP first if needed)
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    text: displayTitle,
                    font: .subheadline,
                    fontWeight: .medium,
                    foregroundStyle: .primary
                )

                if let authorName = currentVideo?.author.name, !authorName.isEmpty {
                    MarqueeText(
                        text: authorName,
                        font: .caption,
                        foregroundStyle: .secondary
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                expandPlayerWithPiPRestore()
            }

            Spacer()
                .contentShape(Rectangle())
                .onTapGesture {
                    expandPlayerWithPiPRestore()
                }

            // Dynamic buttons from settings
            buttonsView

            // Always show close button in overlay layout
            closeButton
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                Rectangle()
                    .fill(.red)
                    .frame(width: geo.size.width * (playerState?.progress ?? 0), height: 2)
            }
            .frame(height: 2)
        }
    }

    // MARK: - Shared Components

    /// Video preview that shows live video when available, or thumbnail as fallback.
    @ViewBuilder
    private var videoPreviewView: some View {
        ZStack {
            // Thumbnail layer - shown when video not ready or during expand animation
            thumbnailView
                .opacity(shouldShowVideoPreview ? 0 : 1)
                .animation(.easeInOut(duration: 0.15), value: shouldShowVideoPreview)

            // Video layer - mounted during collapse or when ready to show
            // Keep it in hierarchy during collapse so the container can receive the player view
            if let backend = playerService?.currentBackend as? MPVBackend,
               let playerState,
               shouldMountVideoView {
                MPVRenderViewRepresentable(backend: backend, playerState: playerState)
                    .allowsHitTesting(false)
                    // No animation on video opacity - show immediately when ready
            }
        }
        .onChange(of: navigationCoordinator?.isPlayerCollapsing) { _, isCollapsing in
            // When collapse animation finishes, resume rendering if video preview should be shown
            // This must happen AFTER playerSheetDidDisappear pauses rendering
            if isCollapsing == false, shouldShowVideoPreview,
               let backend = playerService?.currentBackend as? MPVBackend {
                backend.resumeRendering()
            }
        }
        .onChange(of: shouldShowVideoPreview) { _, showPreview in
            // Resume/pause rendering based on whether mini player video is visible
            // Only act when not in the middle of collapse animation
            if navigationCoordinator?.isPlayerCollapsing == false {
                if let backend = playerService?.currentBackend as? MPVBackend {
                    if showPreview {
                        backend.resumeRendering()
                    } else {
                        backend.pauseRendering()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        LazyImage(url: displayThumbnailURL) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "play.rectangle")
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }

    // MARK: - Dynamic Buttons

    /// Renders buttons from miniPlayerSettings.buttons
    @ViewBuilder
    private var buttonsView: some View {
        ForEach(miniPlayerSettings.buttons) { config in
            miniPlayerButton(for: config)
        }
    }

    /// Renders a single button based on its configuration
    @ViewBuilder
    private func miniPlayerButton(for config: ControlButtonConfiguration) -> some View {
        switch config.buttonType {
        case .playPause:
            playPauseButton(config: config)
        case .playNext:
            playNextButton(config: config)
        case .playPrevious:
            playPreviousButton(config: config)
        case .seek:
            seekButton(config: config)
        case .close:
            closeButton
        case .queue:
            queueButton(config: config)
        case .share:
            shareButton(config: config)
        case .addToPlaylist:
            addToPlaylistButton(config: config)
        case .airplay:
            airplayButton
        case .pictureInPicture:
            pipButton(config: config)
        case .playbackSpeed:
            playbackSpeedButton(config: config)
        default:
            EmptyView()
        }
    }

    // MARK: - Individual Button Views

    private func playPauseButton(config: ControlButtonConfiguration) -> some View {
        Button {
            incrementTapCount(for: config)
            playerService?.togglePlayPause()
        } label: {
            Image(systemName: playPauseIcon)
                .font(isTabAccessory ? .title3 : .title2)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace, options: .speed(2)))
        }
        .buttonStyle(.plain)
        .disabled(isTransportDisabled)
    }

    private func playNextButton(config: ControlButtonConfiguration) -> some View {
        Button {
            incrementTapCount(for: config)
            Task { await playerService?.playNext() }
        } label: {
            Image(systemName: "forward.fill")
                .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: buttonTapCounts[config.id] ?? 0)
                .font(isTabAccessory ? .title3 : .title2)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .foregroundStyle(playerState?.hasNext == true ? .primary : .tertiary)
        }
        .buttonStyle(.plain)
        .disabled(playerState?.hasNext != true)
    }

    private func playPreviousButton(config: ControlButtonConfiguration) -> some View {
        Button {
            incrementTapCount(for: config)
            Task { await playerService?.playPrevious() }
        } label: {
            Image(systemName: "backward.fill")
                .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: buttonTapCounts[config.id] ?? 0)
                .font(isTabAccessory ? .title3 : .title2)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .foregroundStyle(playerState?.hasPrevious == true ? .primary : .tertiary)
        }
        .buttonStyle(.plain)
        .disabled(playerState?.hasPrevious != true)
    }

    private func seekButton(config: ControlButtonConfiguration) -> some View {
        let settings = config.seekSettings ?? SeekSettings()
        return Button {
            incrementTapCount(for: config)
            playerService?.seek(seconds: Double(settings.seconds), direction: settings.direction)
        } label: {
            Image(systemName: settings.systemImage)
                .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: buttonTapCounts[config.id] ?? 0)
                .font(isTabAccessory ? .title3 : .title2)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        Button {
            queueManager?.clearQueue()
            playerService?.stop()
        } label: {
            Image(systemName: "xmark")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func queueButton(config: ControlButtonConfiguration) -> some View {
        Button {
            incrementTapCount(for: config)
            navigationCoordinator?.isMiniPlayerQueueSheetPresented = true
        } label: {
            Image(systemName: "list.bullet")
                .font(isTabAccessory ? .title3 : .title2)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func shareButton(config: ControlButtonConfiguration) -> some View {
        if let video = currentVideo {
            ShareLink(item: video.shareURL) {
                Image(systemName: "square.and.arrow.up")
                    .font(isTabAccessory ? .title3 : .title2)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func addToPlaylistButton(config: ControlButtonConfiguration) -> some View {
        Button {
            incrementTapCount(for: config)
            navigationCoordinator?.isMiniPlayerPlaylistSheetPresented = true
        } label: {
            Image(systemName: "text.badge.plus")
                .font(isTabAccessory ? .title3 : .title2)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var airplayButton: some View {
        #if os(iOS)
        AirPlayButton(tintColor: .label)
            .frame(width: 32, height: 32)
        #elseif os(macOS)
        AirPlayButton()
            .frame(width: 32, height: 32)
        #endif
    }

    private func pipButton(config: ControlButtonConfiguration) -> some View {
        Button {
            incrementTapCount(for: config)
            if let backend = playerService?.currentBackend as? MPVBackend {
                backend.startPiP()
            }
        } label: {
            Image(systemName: "pip.enter")
                .font(isTabAccessory ? .title3 : .title2)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func playbackSpeedButton(config: ControlButtonConfiguration) -> some View {
        let currentRate = playerState?.rate ?? .x1
        return Menu {
            ForEach(PlaybackRate.allCases) { rate in
                Button {
                    playerState?.rate = rate
                    playerService?.currentBackend?.rate = Float(rate.rawValue)
                } label: {
                    HStack {
                        Text(rate.displayText)
                        if currentRate == rate {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(currentRate.compactDisplayText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .tint(.primary)
    }

    // MARK: - Helpers

    /// Whether transport controls should be disabled (during loading/buffering or buffer not ready)
    private var isTransportDisabled: Bool {
        guard let state = playerState else { return true }
        return state.playbackState == .loading ||
               state.playbackState == .buffering ||
               !state.isFirstFrameReady ||
               !state.isBufferReady
    }

    private var playPauseIcon: String {
        switch playerState?.playbackState {
        case .playing:
            return "pause.fill"
        default:
            return "play.fill"
        }
    }

    private func incrementTapCount(for config: ControlButtonConfiguration) {
        buttonTapCounts[config.id, default: 0] += 1
    }
}

// MARK: - Context Menu Modifier

/// A view modifier that conditionally applies the video context menu.
/// Only applies the context menu when a video is available.
private struct MiniPlayerContextMenuModifier: ViewModifier {
    let video: Video?
    let closeAction: () -> Void

    func body(content: Content) -> some View {
        if let video {
            content.videoContextMenu(
                video: video,
                customActions: [
                    VideoContextAction(
                        String(localized: "player.close"),
                        systemImage: "xmark",
                        role: .destructive,
                        action: closeAction
                    )
                ],
                context: .player
            )
        } else {
            content
        }
    }
}

// MARK: - Previews

#Preview("Overlay Mode") {
    VStack {
        Spacer()
        MiniPlayerView(isTabAccessory: false)
    }
    .appEnvironment(.preview)
}

#Preview("Accessory Mode") {
    MiniPlayerView(isTabAccessory: true)
        .appEnvironment(.preview)
}
#endif
