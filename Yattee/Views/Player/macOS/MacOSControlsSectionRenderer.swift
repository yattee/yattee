//
//  MacOSControlsSectionRenderer.swift
//  Yattee
//
//  Renders a section of player control buttons dynamically for the macOS player,
//  styled to match the QuickTime-like capsule bar and the overlay top bar.
//

#if os(macOS)

import SwiftUI

/// Rendering context for macOS control buttons.
enum MacOSControlsContext {
    /// The glass capsule control bar (primary-tinted compact buttons).
    case bar
    /// The overlay top bar over the video (white icons on gradient, circular material backgrounds).
    case overlay
}

/// Renders a horizontal row of control buttons based on layout configuration.
/// macOS counterpart of the iOS `ControlsSectionRenderer`.
struct MacOSControlsSectionRenderer: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let section: LayoutSection
    let actions: PlayerControlsActions
    let globalSettings: GlobalLayoutSettings
    var context: MacOSControlsContext = .bar

    // MARK: - State

    @State private var playNextTapCount = 0
    @State private var playPreviousTapCount = 0
    @State private var seekTapCount = 0
    @State private var isVolumeExpanded = false
    @State private var unlockProgress: Double = 0
    @State private var unlockTimer: Timer?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(section.visibleButtons(isWideLayout: true)) { config in
                renderButton(config)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isVolumeExpanded)
    }

    // MARK: - Metrics

    private var isLocked: Bool {
        actions.isControlsLocked
    }

    private var isTransportDisabled: Bool {
        actions.playerState.isTransportDisabled
    }

    /// Button frame size derived from the layout's button size setting.
    private var frameSize: CGFloat {
        switch globalSettings.buttonSize {
        case .small: return context == .bar ? 24 : 26
        case .medium: return context == .bar ? 28 : 30
        case .large: return context == .bar ? 34 : 36
        }
    }

    /// Icon point size derived from the layout's button size setting.
    private var iconSize: CGFloat {
        switch globalSettings.buttonSize {
        case .small: return context == .bar ? 11 : 13
        case .medium: return context == .bar ? 13 : 15
        case .large: return context == .bar ? 16 : 18
        }
    }

    /// Primary tint for the current context.
    private var tint: Color {
        context == .bar ? .primary : .white
    }

    /// Secondary tint for the current context.
    private var secondaryTint: Color {
        context == .bar ? Color.secondary : .white.opacity(0.7)
    }

    private var fontStyle: ControlsFontStyle {
        globalSettings.fontStyle
    }

    // MARK: - Button Rendering

    @ViewBuilder
    private func renderButton(_ config: ControlButtonConfiguration) -> some View {
        switch config.buttonType {
        case .spacer:
            renderSpacer(config)

        case .close:
            if actions.showCloseButton, actions.onClose != nil {
                controlButton(systemImage: "xmark", help: config.buttonType.displayName) {
                    actions.onClose?()
                }
                .accessibilityLabel(Text("player.controls.close"))
            }

        case .keepOnTop:
            keepOnTopButton

        case .mpvDebug:
            if actions.showDebugButton, actions.onToggleDebug != nil {
                controlButton(systemImage: "info.circle", help: config.buttonType.displayName) {
                    actions.onToggleDebug?()
                }
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)
            }

        case .volume:
            if actions.showVolumeControls {
                volumeControls(config: config)
                    .disabled(isLocked)
                    .opacity(isLocked ? 0.5 : 1.0)
            }

        case .pictureInPicture:
            if actions.onTogglePiP != nil {
                controlButton(systemImage: actions.pipIcon, help: config.buttonType.displayName) {
                    actions.onTogglePiP?()
                }
                .disabled(isLocked || !actions.isPiPAvailable)
                .opacity(isLocked ? 0.5 : 1.0)
            }

        case .fullscreen:
            if actions.shouldShowFullscreenButton {
                controlButton(systemImage: actions.fullscreenIcon, help: config.buttonType.displayName) {
                    actions.onToggleFullscreen?()
                }
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)
            }

        case .settings:
            if actions.onShowSettings != nil {
                controlButton(systemImage: "gearshape", help: config.buttonType.displayName) {
                    actions.onShowSettings?()
                }
            }

        case .controlsLock:
            if actions.onControlsLockToggled != nil {
                controlsLockButton
            }

        case .playPrevious:
            if actions.onPlayPrevious != nil {
                Button {
                    playPreviousTapCount += 1
                    Task { await actions.onPlayPrevious?() }
                } label: {
                    buttonLabel(systemImage: "backward.fill")
                        .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: playPreviousTapCount)
                }
                .buttonStyle(buttonStyleForContext)
                .help(config.buttonType.displayName)
                .disabled(isLocked || !actions.hasPreviousInQueue)
                .opacity(isLocked ? 0.5 : 1.0)
            }

        case .playNext:
            if actions.onPlayNext != nil {
                Button {
                    playNextTapCount += 1
                    Task { await actions.onPlayNext?() }
                } label: {
                    buttonLabel(systemImage: "forward.fill")
                        .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: playNextTapCount)
                }
                .buttonStyle(buttonStyleForContext)
                .help(config.buttonType.displayName)
                .disabled(isLocked || !actions.hasNextInQueue)
                .opacity(isLocked ? 0.5 : 1.0)
            }

        case .playPause:
            if actions.onPlayPause != nil {
                Button {
                    actions.onPlayPause?()
                } label: {
                    let label = Image(systemName: playPauseIcon)
                        .font(.system(size: iconSize + 3, weight: .medium))
                        .frame(width: frameSize + 4, height: frameSize + 4)
                        .contentShape(Rectangle())
                        .contentTransition(.symbolEffect(.replace, options: .speed(2)))
                        .modifier(OverlayCircleBackgroundModifier(active: context == .overlay))

                    if context == .overlay {
                        label.foregroundStyle(.white)
                    } else {
                        label
                    }
                }
                .buttonStyle(buttonStyleForContext)
                .disabled(isTransportDisabled || isLocked)
                .opacity(isTransportDisabled ? 0.3 : (isLocked ? 0.5 : 1.0))
            }

        case .queue:
            if actions.onShowQueue != nil {
                controlButton(systemImage: "list.bullet", help: config.buttonType.displayName) {
                    actions.onShowQueue?()
                }
                .overlay(alignment: .bottom) {
                    queueBadge
                }
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)
            }

        case .addToPlaylist:
            if actions.canAddToPlaylist, actions.onShowPlaylistSelector != nil {
                controlButton(systemImage: "text.badge.plus", help: config.buttonType.displayName) {
                    actions.onShowPlaylistSelector?()
                }
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)
            }

        case .timeDisplay:
            timeDisplayView(config)

        case .playbackSpeed:
            playbackSpeedMenu
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)

        case .share:
            shareButton
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)

        case .contextMenu:
            if let video = actions.currentVideo {
                VideoContextMenuView(
                    video: video,
                    accentColor: tint,
                    buttonSize: frameSize,
                    buttonBackgroundStyle: .none,
                    theme: .dark
                )
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)
            }

        case .titleAuthor:
            titleAuthorButton(config: config)

        case .autoPlayNext:
            if actions.onToggleAutoPlayNext != nil {
                controlButton(
                    systemImage: "play.square.stack.fill",
                    tint: actions.isAutoPlayNextEnabled ? .red : tint,
                    help: config.buttonType.displayName
                ) {
                    actions.onToggleAutoPlayNext?()
                }
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)
            }

        case .audioMode:
            if actions.onToggleAudioMode != nil {
                controlButton(
                    systemImage: "music.note",
                    tint: actions.isAudioModeEnabled ? .red : tint,
                    help: config.buttonType.displayName
                ) {
                    actions.onToggleAudioMode?()
                }
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)
            }

        case .seek:
            if let settings = config.seekSettings {
                seekButton(settings: settings, config: config)
                    .disabled(isLocked)
                    .opacity(isLocked ? 0.5 : 1.0)
            }

        default:
            // Button types not supported on macOS (brightness, orientation lock,
            // panscan, etc.) degrade gracefully when present in stale presets.
            EmptyView()
        }
    }

    // MARK: - Base Button

    /// Button style matching the rendering context.
    private var buttonStyleForContext: MacOSRendererButtonStyle {
        MacOSRendererButtonStyle(context: context)
    }

    /// Badge showing the number of items currently in the queue, mirroring the
    /// iOS pill queue button. Hidden when the queue is empty.
    @ViewBuilder
    private var queueBadge: some View {
        let count = actions.playerState.queue.count
        if count > 0 {
            Text("\(count)")
                .font(.system(size: context == .bar ? 8 : 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.accentColor, in: Capsule())
                .offset(y: 4)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func controlButton(
        systemImage: String,
        tint: Color? = nil,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            buttonLabel(systemImage: systemImage, tint: tint)
        }
        .buttonStyle(buttonStyleForContext)
        .help(help)
    }

    @ViewBuilder
    private func buttonLabel(systemImage: String, tint: Color? = nil) -> some View {
        let base = Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: context == .bar ? .medium : .semibold))
            .frame(width: frameSize, height: frameSize)
            .contentShape(Rectangle())
            .modifier(OverlayCircleBackgroundModifier(active: context == .overlay))

        if context == .overlay {
            base.foregroundStyle(tint ?? .white)
        } else if let tint {
            base.foregroundStyle(tint)
        } else {
            // No explicit tint in the bar: the button style drives
            // primary/secondary based on the enabled state.
            base
        }
    }

    @ViewBuilder
    private func renderSpacer(_ config: ControlButtonConfiguration) -> some View {
        if let settings = config.spacerSettings {
            if settings.isFlexible {
                Spacer()
            } else {
                Spacer()
                    .frame(width: CGFloat(settings.fixedWidth))
            }
        } else {
            Spacer()
        }
    }

    private var playPauseIcon: String {
        switch actions.playerState.playbackState {
        case .playing:
            return "pause.fill"
        default:
            return "play.fill"
        }
    }

    // MARK: - Keep on Top

    @ViewBuilder
    private var keepOnTopButton: some View {
        // Only meaningful for the separate window presentation, so hidden in
        // the inline sheet and in fullscreen.
        if let settings = appEnvironment?.settingsManager,
           settings.macPlayerSeparateWindow, !actions.isFullscreen {
            controlButton(
                systemImage: settings.macPlayerFloating ? "pin.fill" : "pin",
                help: String(localized: "player.controls.keepOnTop")
            ) {
                settings.macPlayerFloating.toggle()
            }
            .accessibilityLabel(Text("player.controls.keepOnTop"))
            .disabled(isLocked)
            .opacity(isLocked ? 0.5 : 1.0)
        }
    }

    // MARK: - Volume

    @ViewBuilder
    private func volumeControls(config: ControlButtonConfiguration) -> some View {
        // macOS is always a "wide" layout, so auto-expand behaves as always visible.
        let behavior = config.sliderSettings?.sliderBehavior ?? .alwaysVisible
        let effectiveBehavior: SliderBehavior = behavior == .autoExpandInLandscape ? .alwaysVisible : behavior

        HStack(spacing: 2) {
            Button {
                if actions.playerState.isMuted {
                    actions.onMuteToggled?()
                } else if effectiveBehavior == .expandOnTap {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isVolumeExpanded.toggle()
                    }
                } else {
                    actions.onMuteToggled?()
                }
            } label: {
                buttonLabel(systemImage: volumeIcon, tint: actions.playerState.isMuted ? .red : nil)
            }
            .buttonStyle(buttonStyleForContext)
            .help(ControlButtonType.volume.displayName)

            if effectiveBehavior == .alwaysVisible || isVolumeExpanded {
                Slider(
                    value: Binding(
                        get: { Double(actions.playerState.volume) },
                        set: { newValue in
                            actions.playerState.volume = Float(newValue)
                            actions.onVolumeChanged?(Float(newValue))
                        }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        actions.onSliderAdjustmentChanged?(editing)
                        if editing {
                            actions.onCancelHideTimer?()
                        } else {
                            actions.onResetHideTimer?()
                        }
                    }
                )
                .frame(width: 70)
                .controlSize(.mini)
                .disabled(actions.playerState.isMuted)
                .opacity(actions.playerState.isMuted ? 0.5 : 1.0)
                .transition(.opacity)
            }
        }
    }

    private var volumeIcon: String {
        let playerState = actions.playerState
        if playerState.isMuted || playerState.volume == 0 {
            return "speaker.slash.fill"
        } else if playerState.volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if playerState.volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    // MARK: - Controls Lock

    @ViewBuilder
    private var controlsLockButton: some View {
        if isLocked {
            // Locked state: show progress ring, hold to unlock
            Button { } label: {
                buttonLabel(systemImage: "lock", tint: .red)
                    .overlay {
                        Circle()
                            .trim(from: 0, to: unlockProgress)
                            .stroke(tint, lineWidth: 2)
                            .rotationEffect(.degrees(-90))
                            .frame(width: frameSize + 4, height: frameSize + 4)
                            .opacity(unlockProgress > 0 ? 1 : 0)
                    }
            }
            .buttonStyle(buttonStyleForContext)
            .help(String(localized: "controls.button.controlsLock"))
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in startUnlock() }
                    .onEnded { _ in cancelUnlock() }
            )
        } else {
            controlButton(systemImage: "lock.open", help: String(localized: "controls.button.controlsLock")) {
                actions.onControlsLockToggled?(true)
            }
        }
    }

    private func startUnlock() {
        guard unlockTimer == nil else { return }
        unlockProgress = 0
        actions.onCancelHideTimer?()

        unlockTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                self.unlockProgress += 0.05 / 3.0 // 3 seconds total
                if self.unlockProgress >= 1.0 {
                    self.unlockTimer?.invalidate()
                    self.unlockTimer = nil
                    self.actions.onControlsLockToggled?(false)
                    self.unlockProgress = 0
                    self.actions.onResetHideTimer?()
                }
            }
        }
    }

    private func cancelUnlock() {
        unlockTimer?.invalidate()
        unlockTimer = nil
        withAnimation(.easeOut(duration: 0.2)) {
            unlockProgress = 0
        }
        actions.onResetHideTimer?()
    }

    // MARK: - Time Display

    @ViewBuilder
    private func timeDisplayView(_ config: ControlButtonConfiguration) -> some View {
        let playerState = actions.playerState
        let timeFont = fontStyle.font(.caption)

        Group {
            if playerState.isLive {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                    Text(String(localized: "player.live"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            } else {
                let format = config.timeDisplaySettings?.format ?? .currentAndTotal

                HStack(spacing: 0) {
                    Text(playerState.formattedCurrentTime)
                        .font(timeFont)
                        .foregroundStyle(tint)

                    switch format {
                    case .currentOnly:
                        EmptyView()

                    case .currentAndTotal, .currentAndTotalExcludingSponsor:
                        Text(verbatim: " / ")
                            .font(timeFont)
                            .foregroundStyle(secondaryTint)
                        Text(playerState.formattedDuration)
                            .font(timeFont)
                            .foregroundStyle(secondaryTint)

                    case .currentAndRemaining, .currentAndRemainingExcludingSponsor:
                        Text(verbatim: " / ")
                            .font(timeFont)
                            .foregroundStyle(secondaryTint)
                        Text(verbatim: "-\(formattedRemainingTime)")
                            .font(timeFont)
                            .foregroundStyle(secondaryTint)
                    }
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .truncationMode(.middle)
    }

    private var formattedRemainingTime: String {
        let remaining = max(0, actions.playerState.duration - actions.playerState.currentTime)
        return remaining.formattedAsTimestamp
    }

    // MARK: - Title / Author

    @ViewBuilder
    private func titleAuthorButton(config: ControlButtonConfiguration) -> some View {
        let settings = config.titleAuthorSettings ?? TitleAuthorSettings()

        if let video = actions.currentVideo {
            Button {
                actions.onToggleDetailsVisibility?()
            } label: {
                HStack(alignment: .center, spacing: context == .overlay ? 12 : 8) {
                    if settings.showSourceImage {
                        ChannelAvatarView(
                            author: video.author,
                            size: context == .overlay ? 36 : frameSize * 0.9,
                            yatteeServerURL: actions.yatteeServerURL,
                            source: video.id.source
                        )
                    }

                    if settings.showTitle || settings.showSourceName {
                        VStack(alignment: .leading, spacing: 2) {
                            if settings.showTitle {
                                Text(actions.deArrowBrandingProvider?.title(for: video) ?? video.title)
                                    .font(context == .overlay ? .headline : fontStyle.font(.caption).weight(.medium))
                                    .foregroundStyle(tint)
                                    .lineLimit(1)
                            }

                            if settings.showSourceName {
                                Text(video.author.name)
                                    .font(context == .overlay ? .subheadline : fontStyle.font(.caption2))
                                    .foregroundStyle(secondaryTint)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(actions.onToggleDetailsVisibility == nil || isLocked)
            .opacity(isLocked ? 0.5 : 1.0)
            .help(Text("player.controls.info"))
        }
    }

    // MARK: - Playback Speed

    @ViewBuilder
    private var playbackSpeedMenu: some View {
        Menu {
            ForEach(PlaybackRate.allCases) { rate in
                Button {
                    actions.onRateChanged?(rate)
                } label: {
                    HStack {
                        Text(rate.displayText)
                        if actions.playerState.rate == rate {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: iconSize, weight: context == .bar ? .medium : .semibold))
                if let rateDisplay = actions.playbackRateDisplay {
                    Text(rateDisplay)
                        .font(fontStyle.font(.caption).weight(.semibold))
                }
            }
            .foregroundStyle(tint)
            .frame(minWidth: frameSize, minHeight: frameSize)
            .contentShape(Rectangle())
            .modifier(OverlayCircleBackgroundModifier(active: context == .overlay))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(ControlButtonType.playbackSpeed.displayName)
    }

    // MARK: - Share

    @ViewBuilder
    private var shareButton: some View {
        if let video = actions.currentVideo {
            ShareLink(item: video.shareURL) {
                buttonLabel(systemImage: "square.and.arrow.up")
            }
            .buttonStyle(buttonStyleForContext)
            .help(ControlButtonType.share.displayName)
        }
    }

    // MARK: - Seek

    @ViewBuilder
    private func seekButton(settings: SeekSettings, config: ControlButtonConfiguration) -> some View {
        Button {
            seekTapCount += 1
            Task {
                if settings.direction == .forward {
                    await actions.onSeekForward?(TimeInterval(settings.seconds))
                } else {
                    await actions.onSeekBackward?(TimeInterval(settings.seconds))
                }
            }
        } label: {
            buttonLabel(systemImage: settings.systemImage)
                .symbolEffect(.rotate.byLayer, options: .speed(2).nonRepeating, value: seekTapCount)
        }
        .buttonStyle(buttonStyleForContext)
        .help(config.buttonType.displayName)
    }
}

// MARK: - Helpers

/// Applies the top-bar circular material background when rendering in the overlay context.
private struct OverlayCircleBackgroundModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.background(.ultraThinMaterial, in: Circle())
        } else {
            content
        }
    }
}

/// Button style for the macOS renderer, switching by rendering context.
/// The bar variant tints primary/secondary by enabled state with subtle press
/// feedback; the overlay variant only adds press feedback since its labels
/// carry explicit white styling.
struct MacOSRendererButtonStyle: ButtonStyle {
    let context: MacOSControlsContext

    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        switch context {
        case .bar:
            configuration.label
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .opacity(configuration.isPressed ? 0.6 : 1.0)
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)

        case .overlay:
            configuration.label
                .opacity(configuration.isPressed ? 0.7 : 1.0)
        }
    }
}

#endif
