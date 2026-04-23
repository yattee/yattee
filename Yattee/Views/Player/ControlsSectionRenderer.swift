//
//  ControlsSectionRenderer.swift
//  Yattee
//
//  Renders a section of player control buttons dynamically based on layout configuration.
//

import SwiftUI

#if os(iOS)

/// Renders a horizontal row of control buttons based on layout configuration.
struct ControlsSectionRenderer: View {
    let section: LayoutSection
    let actions: PlayerControlsActions
    let globalSettings: GlobalLayoutSettings
    let controlsVisible: Bool

    /// Convenience accessor for button size.
    private var buttonSize: ButtonSize { globalSettings.buttonSize }

    /// Convenience accessor for font style.
    private var fontStyle: ControlsFontStyle { globalSettings.fontStyle }

    /// State for volume slider adjustment
    @State private var isAdjustingVolume = false

    /// State for brightness slider adjustment
    @State private var isAdjustingBrightness = false

    /// State for play next button animation
    @State private var playNextTapCount = 0

    /// State for play previous button animation
    @State private var playPreviousTapCount = 0

    /// State for seek button animation
    @State private var seekTapCount = 0

    /// State for controls lock button unlock progress
    @State private var unlockProgress: Double = 0
    @State private var unlockTimer: Timer?

    /// State for expandable volume slider
    @State private var isVolumeExpanded = false

    /// State for expandable brightness slider
    @State private var isBrightnessExpanded = false

    var body: some View {
        HStack {
            ForEach(section.visibleButtons(isWideLayout: actions.isWideScreenLayout)) { config in
                renderButton(config)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isVolumeExpanded)
        .animation(.easeInOut(duration: 0.2), value: isBrightnessExpanded)
        .onChange(of: controlsVisible) { _, visible in
            if !visible {
                isVolumeExpanded = false
                isBrightnessExpanded = false
            }
        }
    }

    /// Whether buttons should be disabled due to controls lock (all except settings)
    private var isLocked: Bool {
        actions.isControlsLocked
    }

    // MARK: - Button Rendering

    @ViewBuilder
    private func renderButton(_ config: ControlButtonConfiguration) -> some View {
        switch config.buttonType {
        case .spacer:
            renderSpacer(config)

        case .close:
            if actions.showCloseButton, actions.onClose != nil {
                controlButton(systemImage: "xmark") {
                    actions.onClose?()
                }
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)
                .accessibilityIdentifier("player.closeButton")
                .accessibilityLabel("player.closeButton")
            }

        case .airplay:
            airplayButtonWithBackground
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)

        case .mpvDebug:
            if actions.showDebugButton, actions.onToggleDebug != nil {
                controlButton(systemImage: "info.circle") {
                    actions.onToggleDebug?()
                }
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)
            }

        case .brightness:
            brightnessControls(config: config)
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)

        case .volume:
            if actions.showVolumeControls {
                volumeControls(config: config)
                    .disabled(isLocked)
                    .opacity(isLocked ? 0.5 : 1.0)
            }

        case .pictureInPicture:
            if actions.isPiPAvailable, actions.onTogglePiP != nil {
                controlButton(systemImage: actions.pipIcon) {
                    actions.onTogglePiP?()
                }
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)
            }

        case .fullscreen:
            if actions.shouldShowFullscreenButton {
                controlButton(systemImage: actions.fullscreenIcon) {
                    handleFullscreenTap()
                }
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)
            }

        case .orientationLock:
            // Only on iPhone (not iPad)
            if !actions.isIPad, actions.onToggleOrientationLock != nil {
                controlButton(
                    systemImage: actions.orientationLockIcon,
                    tint: actions.isOrientationLocked ? .red : .white
                ) {
                    actions.onToggleOrientationLock?()
                }
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)
            }

        case .panelToggle:
            if actions.onTogglePanel != nil {
                Button {
                    actions.onTogglePanel?()
                } label: {
                    panelToggleButtonContent
                }
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)
            }

        case .settings:
            if actions.onShowSettings != nil {
                controlButton(systemImage: "gearshape") {
                    actions.onShowSettings?()
                }
            }

        case .controlsLock:
            if actions.onControlsLockToggled != nil {
                controlsLockButton
            }

        case .playPrevious:
            if actions.hasPreviousInQueue, actions.onPlayPrevious != nil {
                Button {
                    playPreviousTapCount += 1
                    Task { await actions.onPlayPrevious?() }
                } label: {
                    playPreviousButtonContent()
                }
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)
            }

        case .playNext:
            if actions.hasNextInQueue, actions.onPlayNext != nil {
                Button {
                    playNextTapCount += 1
                    Task { await actions.onPlayNext?() }
                } label: {
                    playNextButtonContent()
                }
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)
            }

        case .queue:
            if actions.onShowQueue != nil {
                controlButton(systemImage: "list.bullet") {
                    actions.onShowQueue?()
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

        case .videoTrack:
            videoTrackButton
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)

        case .audioTrack:
            audioTrackButton
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)

        case .captions:
            captionsButton
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)

        case .chapters:
            chaptersButton
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)

        case .share:
            shareButton
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)

        case .addToPlaylist:
            addToPlaylistButton
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)

        case .contextMenu:
            contextMenuButton
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)

        case .playPause:
            if actions.onPlayPause != nil {
                Button {
                    actions.onPlayPause?()
                } label: {
                    playPauseButtonContent()
                }
                .disabled(isTransportDisabled || isLocked)
                .opacity(isLocked ? 0.5 : 1.0)
            }

        case .titleAuthor:
            if actions.onTogglePanel != nil {
                Button {
                    actions.onTogglePanel?()
                } label: {
                    titleAuthorButtonContent(config: config)
                }
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)
            }

        case .panscan:
            panscanButton
                .disabled(isLocked || !actions.isPanscanAllowed)
                .opacity(isLocked || !actions.isPanscanAllowed ? 0.5 : 1.0)

        case .autoPlayNext:
            autoPlayNextButton
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)

        case .seekBackward, .seekForward:
            // These are center section only buttons, not rendered here
            EmptyView()

        case .seek:
            if let settings = config.seekSettings {
                seekButton(settings: settings, config: config)
                    .disabled(isLocked)
                    .opacity(isLocked ? 0.5 : 1.0)
            }
        }
    }

    // MARK: - Helper Views

    /// Convenience accessor for button background style.
    private var buttonBackground: ButtonBackgroundStyle { globalSettings.buttonBackground }

    /// Convenience accessor for theme.
    private var theme: ControlsTheme { globalSettings.theme }

    /// The size of the button background circle (slightly larger than button tap target).
    private var buttonBackgroundSize: CGFloat {
        buttonSize.pointSize * 1.15
    }

    // MARK: - Controls Lock Button

    @ViewBuilder
    private var controlsLockButton: some View {
        let frameSize = buttonBackground.glassStyle != nil ? buttonBackgroundSize : buttonSize.pointSize

        if isLocked {
            // Locked state: show progress ring, hold to unlock
            Button { } label: {
                Image(systemName: "lock")
                    .font(.system(size: buttonSize.iconSize))
                    .foregroundStyle(.red)
                    .frame(width: frameSize, height: frameSize)
                    .modifier(OptionalGlassBackgroundModifier(style: buttonBackground, theme: theme))
                    .overlay {
                        // Progress ring overlay - doesn't affect layout
                        Circle()
                            .trim(from: 0, to: unlockProgress)
                            .stroke(Color.white, lineWidth: 2)
                            .rotationEffect(.degrees(-90))
                            .frame(width: frameSize + 4, height: frameSize + 4)
                            .opacity(unlockProgress > 0 ? 1 : 0)
                    }
                    .contentShape(buttonBackground.glassStyle != nil ? AnyShape(Circle()) : AnyShape(Rectangle()))
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in startUnlock() }
                    .onEnded { _ in cancelUnlock() }
            )
        } else {
            // Unlocked state: tap to lock
            controlButton(systemImage: "lock.open") {
                actions.onControlsLockToggled?(true)
            }
        }
    }

    private func startUnlock() {
        guard unlockTimer == nil else { return }
        unlockProgress = 0

        // Cancel hide timer while unlocking
        actions.onCancelHideTimer?()

        unlockTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                self.unlockProgress += 0.05 / 3.0 // 3 seconds total
                if self.unlockProgress >= 1.0 {
                    self.unlockTimer?.invalidate()
                    self.unlockTimer = nil
                    self.actions.onControlsLockToggled?(false)
                    self.unlockProgress = 0
                    // Reset hide timer after unlock completes
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
        // Reset hide timer when user releases early
        actions.onResetHideTimer?()
    }

    @ViewBuilder
    private func controlButton(
        systemImage: String,
        tint: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            buttonContent(systemImage: systemImage, tint: tint)
        }
    }

    @ViewBuilder
    private func buttonContent(systemImage: String, tint: Color) -> some View {
        if let glassStyle = buttonBackground.glassStyle {
            Image(systemName: systemImage)
                .font(.system(size: buttonSize.iconSize))
                .foregroundStyle(tint)
                .frame(width: buttonBackgroundSize, height: buttonBackgroundSize)
                .glassBackground(glassStyle, in: .circle, fallback: .ultraThinMaterial, colorScheme: theme.colorScheme)
                .contentShape(Circle())
        } else {
            Image(systemName: systemImage)
                .font(.system(size: buttonSize.iconSize))
                .foregroundStyle(tint)
                .frame(width: buttonSize.pointSize, height: buttonSize.pointSize)
                .contentShape(Rectangle())
        }
    }

    /// Volume button content using variable value SF Symbol.
    @ViewBuilder
    private func volumeButtonContent(tint: Color) -> some View {
        if let glassStyle = buttonBackground.glassStyle {
            volumeImage
                .font(.system(size: buttonSize.iconSize))
                .foregroundStyle(tint)
                .frame(width: buttonBackgroundSize, height: buttonBackgroundSize)
                .glassBackground(glassStyle, in: .circle, fallback: .ultraThinMaterial, colorScheme: theme.colorScheme)
                .contentShape(Circle())
        } else {
            volumeImage
                .font(.system(size: buttonSize.iconSize))
                .foregroundStyle(tint)
                .frame(width: buttonSize.pointSize, height: buttonSize.pointSize)
                .contentShape(Rectangle())
        }
    }

    /// Volume icon image using variable value SF Symbol.
    private var volumeImage: Image {
        if actions.playerState.isMuted {
            Image(systemName: "speaker.slash.fill")
        } else {
            Image(systemName: "speaker.wave.3.fill", variableValue: Double(actions.playerState.volume))
        }
    }

    /// Brightness button content using variable value SF Symbol.
    @ViewBuilder
    private func brightnessButtonContent() -> some View {
        if let glassStyle = buttonBackground.glassStyle {
            brightnessImage
                .font(.system(size: buttonSize.iconSize))
                .foregroundStyle(.white)
                .frame(width: buttonBackgroundSize, height: buttonBackgroundSize)
                .glassBackground(glassStyle, in: .circle, fallback: .ultraThinMaterial, colorScheme: theme.colorScheme)
                .contentShape(Circle())
        } else {
            brightnessImage
                .font(.system(size: buttonSize.iconSize))
                .foregroundStyle(.white)
                .frame(width: buttonSize.pointSize, height: buttonSize.pointSize)
                .contentShape(Rectangle())
        }
    }

    /// Brightness icon image using variable value SF Symbol.
    private var brightnessImage: Image {
        Image(systemName: "sun.max.fill", variableValue: UIScreen.main.brightness)
    }

    /// Panel toggle button content with glass background support.
    @ViewBuilder
    private var panelToggleButtonContent: some View {
        let frameSize = buttonBackground.glassStyle != nil ? buttonBackgroundSize : buttonSize.pointSize
        Group {
            Image(systemName: actions.panelToggleIcon)
                .font(.system(size: buttonSize.iconSize))
                .foregroundStyle(.white)
                .scaleEffect(x: actions.panelSide == .right ? 1 : -1)
        }
        .frame(width: frameSize, height: frameSize)
        .modifier(OptionalGlassBackgroundModifier(style: buttonBackground, theme: theme))
        .contentShape(buttonBackground.glassStyle != nil ? AnyShape(Circle()) : AnyShape(Rectangle()))
    }

    /// Title/Author button content showing video title and source info.
    @ViewBuilder
    private func titleAuthorButtonContent(config: ControlButtonConfiguration) -> some View {
        let settings = config.titleAuthorSettings ?? TitleAuthorSettings()
        let video = actions.currentVideo
        let imageSize = buttonSize.pointSize * 0.9

        HStack(spacing: 8) {
            // Source/author image
            if settings.showSourceImage, let video {
                ChannelAvatarView(
                    author: video.author,
                    size: imageSize,
                    yatteeServerURL: actions.yatteeServerURL,
                    source: video.id.source
                )
            }

            // Title and source name stack
            if settings.showTitle || settings.showSourceName {
                VStack(alignment: .leading, spacing: 2) {
                    if settings.showTitle, let video {
                        Text(actions.deArrowBrandingProvider?.title(for: video) ?? video.title)
                            .font(fontStyle.font(.caption).weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    if settings.showSourceName, let video {
                        Text(video.author.name)
                            .font(fontStyle.font(.caption2))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, buttonBackground.glassStyle != nil ? 12 : 0)
        .padding(.vertical, buttonBackground.glassStyle != nil ? 6 : 0)
        .modifier(OptionalCapsuleGlassBackgroundModifier(style: buttonBackground, theme: theme))
        .contentShape(buttonBackground.glassStyle != nil ? AnyShape(Capsule()) : AnyShape(Rectangle()))
    }

    /// Play previous button content with glass background and symbol effect support.
    @ViewBuilder
    private func playPreviousButtonContent() -> some View {
        let frameSize = buttonBackground.glassStyle != nil ? buttonBackgroundSize : buttonSize.pointSize
        Image(systemName: "backward.fill")
            .font(.system(size: buttonSize.iconSize))
            .foregroundStyle(.white)
            .frame(width: frameSize, height: frameSize)
            .modifier(OptionalGlassBackgroundModifier(style: buttonBackground, theme: theme))
            .contentShape(buttonBackground.glassStyle != nil ? AnyShape(Circle()) : AnyShape(Rectangle()))
            .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: playPreviousTapCount)
    }

    /// Play next button content with glass background and symbol effect support.
    @ViewBuilder
    private func playNextButtonContent() -> some View {
        let frameSize = buttonBackground.glassStyle != nil ? buttonBackgroundSize : buttonSize.pointSize
        Image(systemName: "forward.fill")
            .font(.system(size: buttonSize.iconSize))
            .foregroundStyle(.white)
            .frame(width: frameSize, height: frameSize)
            .modifier(OptionalGlassBackgroundModifier(style: buttonBackground, theme: theme))
            .contentShape(buttonBackground.glassStyle != nil ? AnyShape(Circle()) : AnyShape(Rectangle()))
            .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: playNextTapCount)
    }

    /// Play/pause button content with glass background and symbol transition effect.
    @ViewBuilder
    private func playPauseButtonContent() -> some View {
        let frameSize = buttonBackground.glassStyle != nil ? buttonBackgroundSize : buttonSize.pointSize
        Image(systemName: playPauseIcon)
            .contentTransition(.symbolEffect(.replace, options: .speed(2)))
            .font(.system(size: buttonSize.iconSize))
            .foregroundStyle(.white)
            .frame(width: frameSize, height: frameSize)
            .modifier(OptionalGlassBackgroundModifier(style: buttonBackground, theme: theme))
            .contentShape(buttonBackground.glassStyle != nil ? AnyShape(Circle()) : AnyShape(Rectangle()))
    }

    /// Icon for play/pause button based on current playback state.
    private var playPauseIcon: String {
        switch actions.playerState.playbackState {
        case .playing:
            return "pause.fill"
        default:
            return "play.fill"
        }
    }

    /// AirPlay button with optional glass background.
    @ViewBuilder
    private var airplayButtonWithBackground: some View {
        let frameSize = buttonBackground.glassStyle != nil ? buttonBackgroundSize : buttonSize.pointSize
        if buttonBackground.glassStyle != nil {
            AirPlayButton()
                .frame(width: buttonSize.pointSize, height: buttonSize.pointSize)
                .frame(width: frameSize, height: frameSize)
                .modifier(OptionalGlassBackgroundModifier(style: buttonBackground, theme: theme))
        } else {
            AirPlayButton()
                .frame(width: frameSize, height: frameSize)
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

    // MARK: - Time Display

    @ViewBuilder
    private func timeDisplayView(_ config: ControlButtonConfiguration) -> some View {
        let playerState = actions.playerState
        let timeFont = fontStyle.font(.caption)

        Group {
            if playerState.isLive {
                // LIVE indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                    Text(String(localized: "player.live"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            } else {
                // Time display based on format
                let format = config.timeDisplaySettings?.format ?? .currentAndTotal

                switch format {
                case .currentOnly:
                    Text(playerState.formattedCurrentTime)
                        .font(timeFont)
                        .foregroundStyle(.white)

                case .currentAndTotal:
                    HStack(spacing: 0) {
                        Text(playerState.formattedCurrentTime)
                            .font(timeFont)
                            .foregroundStyle(.white)

                        Text(verbatim: " / ")
                            .font(timeFont)
                            .foregroundStyle(.white.opacity(0.7))

                        Text(playerState.formattedDuration)
                            .font(timeFont)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                case .currentAndTotalExcludingSponsor:
                    // TODO: Calculate SponsorBlock-adjusted duration
                    HStack(spacing: 0) {
                        Text(playerState.formattedCurrentTime)
                            .font(timeFont)
                            .foregroundStyle(.white)

                        Text(verbatim: " / ")
                            .font(timeFont)
                            .foregroundStyle(.white.opacity(0.7))

                        Text(playerState.formattedDuration)
                            .font(timeFont)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                case .currentAndRemaining:
                    HStack(spacing: 0) {
                        Text(playerState.formattedCurrentTime)
                            .font(timeFont)
                            .foregroundStyle(.white)

                        Text(verbatim: " / ")
                            .font(timeFont)
                            .foregroundStyle(.white.opacity(0.7))

                        Text(verbatim: "-\(formattedRemainingTime)")
                            .font(timeFont)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                case .currentAndRemainingExcludingSponsor:
                    // TODO: Calculate SponsorBlock-adjusted remaining
                    HStack(spacing: 0) {
                        Text(playerState.formattedCurrentTime)
                            .font(timeFont)
                            .foregroundStyle(.white)

                        Text(verbatim: " / ")
                            .font(timeFont)
                            .foregroundStyle(.white.opacity(0.7))

                        Text(verbatim: "-\(formattedRemainingTime)")
                            .font(timeFont)
                            .foregroundStyle(.white.opacity(0.7))
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

    // MARK: - Volume Controls

    @ViewBuilder
    private func volumeControls(config: ControlButtonConfiguration) -> some View {
        let behavior = config.sliderSettings?.sliderBehavior ?? .expandOnTap

        // Determine effective behavior based on orientation for autoExpandInLandscape
        let effectiveBehavior: SliderBehavior = {
            if behavior == .autoExpandInLandscape {
                return actions.isWideScreenLayout ? .alwaysVisible : .expandOnTap
            }
            return behavior
        }()

        HStack(spacing: buttonBackground.glassStyle != nil ? 8 : 4) {
            // Mute/expand button
            Button {
                if actions.playerState.isMuted {
                    // Always unmute when muted, regardless of behavior
                    actions.onMuteToggled?()
                } else if effectiveBehavior == .expandOnTap {
                    // Toggle slider expansion when not muted
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isVolumeExpanded.toggle()
                    }
                } else {
                    // Toggle mute when always visible
                    actions.onMuteToggled?()
                }
            } label: {
                volumeButtonContent(tint: actions.playerState.isMuted ? .red : .white)
            }

            // Volume slider - shown based on behavior
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
                        isAdjustingVolume = editing
                        actions.onSliderAdjustmentChanged?(editing)
                        if editing {
                            actions.onCancelHideTimer?()
                        } else {
                            actions.onResetHideTimer?()
                        }
                    }
                )
                .frame(width: 80)
                .tint(.white)
                .disabled(actions.playerState.isMuted)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isVolumeExpanded)
    }

    // MARK: - Brightness Controls

    @ViewBuilder
    private func brightnessControls(config: ControlButtonConfiguration) -> some View {
        let behavior = config.sliderSettings?.sliderBehavior ?? .expandOnTap

        // Determine effective behavior based on orientation for autoExpandInLandscape
        let effectiveBehavior: SliderBehavior = {
            if behavior == .autoExpandInLandscape {
                return actions.isWideScreenLayout ? .alwaysVisible : .expandOnTap
            }
            return behavior
        }()

        HStack(spacing: buttonBackground.glassStyle != nil ? 8 : 4) {
            // Brightness icon/expand button
            Button {
                if effectiveBehavior == .expandOnTap {
                    // Toggle slider expansion
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isBrightnessExpanded.toggle()
                    }
                }
                // No action when always visible (brightness has no toggle like mute)
            } label: {
                brightnessButtonContent()
            }

            // Brightness slider - shown based on behavior
            if effectiveBehavior == .alwaysVisible || isBrightnessExpanded {
                Slider(
                    value: Binding(
                        get: { UIScreen.main.brightness },
                        set: { newValue in
                            UIScreen.main.brightness = newValue
                        }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        isAdjustingBrightness = editing
                        actions.onSliderAdjustmentChanged?(editing)
                        if editing {
                            actions.onCancelHideTimer?()
                        } else {
                            actions.onResetHideTimer?()
                        }
                    }
                )
                .frame(width: 80)
                .tint(.white)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isBrightnessExpanded)
    }

    // MARK: - Fullscreen Handling

    private func handleFullscreenTap() {
        let isActualWidescreenLayout = actions.isWideScreenLayout && actions.onTogglePanel != nil

        if actions.isIPad {
            // iPad: always toggle details visibility
            actions.onToggleDetailsVisibility?()
        } else if isActualWidescreenLayout && actions.isFullscreen && !actions.isWidescreenVideo {
            // iPhone in landscape with portrait video fullscreen: rotate back to portrait
            actions.onToggleFullscreen?()
        } else if !actions.isWidescreenVideo {
            // iPhone portrait video in portrait layout: toggle details visibility
            actions.onToggleDetailsVisibility?()
        } else {
            // iPhone with widescreen video: rotate orientation
            actions.onToggleFullscreen?()
        }
    }

    // MARK: - Transport State

    private var isTransportDisabled: Bool {
        let state = actions.playerState
        return state.playbackState == .loading ||
               state.playbackState == .buffering ||
               !state.isFirstFrameReady ||
               !state.isBufferReady
    }

    // MARK: - Playback Speed Menu

    @ViewBuilder
    private var playbackSpeedMenu: some View {
        let hasText = actions.playbackRateDisplay != nil
        let frameSize = buttonBackground.glassStyle != nil ? buttonBackgroundSize : buttonSize.pointSize

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
            playbackSpeedLabel(hasText: hasText, frameSize: frameSize)
        }
        .menuIndicator(.hidden)
    }

    @ViewBuilder
    private func playbackSpeedLabel(hasText: Bool, frameSize: CGFloat) -> some View {
        let content = HStack(spacing: 2) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: buttonSize.iconSize))
            if let rateDisplay = actions.playbackRateDisplay {
                Text(rateDisplay)
                    .font(fontStyle.font(.caption).weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(minWidth: frameSize, minHeight: frameSize)
        .padding(.horizontal, hasText && buttonBackground.glassStyle != nil ? 8 : 0)

        if hasText {
            content
                .modifier(OptionalCapsuleGlassBackgroundModifier(style: buttonBackground, theme: theme))
                .contentShape(buttonBackground.glassStyle != nil ? AnyShape(Capsule()) : AnyShape(Rectangle()))
        } else {
            content
                .modifier(OptionalGlassBackgroundModifier(style: buttonBackground, theme: theme))
                .contentShape(buttonBackground.glassStyle != nil ? AnyShape(Circle()) : AnyShape(Rectangle()))
        }
    }

    // MARK: - Video Track Button

    @ViewBuilder
    private var videoTrackButton: some View {
        if actions.onShowVideoTrackSelector != nil {
            controlButton(systemImage: "film") {
                actions.onShowVideoTrackSelector?()
            }
        }
    }

    // MARK: - Audio Track Button

    @ViewBuilder
    private var audioTrackButton: some View {
        if actions.onShowAudioTrackSelector != nil {
            controlButton(systemImage: "waveform") {
                actions.onShowAudioTrackSelector?()
            }
        }
    }

    // MARK: - Captions Button

    @ViewBuilder
    private var captionsButton: some View {
        if actions.hasCaptions, actions.onCaptionSelected != nil {
            controlButton(systemImage: actions.currentCaption != nil ? "captions.bubble.fill" : "captions.bubble") {
                actions.onShowCaptionsSelector?()
            }
        }
    }

    // MARK: - Chapters Button

    @ViewBuilder
    private var chaptersButton: some View {
        if actions.hasChapters {
            controlButton(systemImage: "list.bullet.rectangle") {
                actions.onShowChaptersSelector?()
            }
        }
    }

    // MARK: - Share Button

    @ViewBuilder
    private var shareButton: some View {
        if let video = actions.currentVideo {
            ShareLink(item: video.shareURL) {
                buttonContent(systemImage: "square.and.arrow.up", tint: .white)
            }
        }
    }

    // MARK: - Add to Playlist Button

    @ViewBuilder
    private var addToPlaylistButton: some View {
        if actions.canAddToPlaylist, actions.onShowPlaylistSelector != nil {
            controlButton(systemImage: "text.badge.plus") {
                actions.onShowPlaylistSelector?()
            }
        }
    }

    // MARK: - Context Menu Button

    @ViewBuilder
    private var contextMenuButton: some View {
        if let video = actions.currentVideo {
            VideoContextMenuView(
                video: video,
                accentColor: .white,
                buttonSize: buttonSize.pointSize,
                buttonBackgroundStyle: buttonBackground,
                theme: theme
            )
        }
    }

    // MARK: - Panscan Button

    @ViewBuilder
    private var panscanButton: some View {
        if actions.onTogglePanscan != nil {
            controlButton(systemImage: actions.panscanIcon) {
                actions.onTogglePanscan?()
            }
        }
    }

    // MARK: - Seek Button (Horizontal Sections)

    @ViewBuilder
    private func seekButton(settings: SeekSettings, config: ControlButtonConfiguration) -> some View {
        let frameSize = buttonBackground.glassStyle != nil ? buttonBackgroundSize : buttonSize.pointSize

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
            Image(systemName: settings.systemImage)
                .font(.system(size: buttonSize.iconSize))
                .foregroundStyle(.white)
                .frame(width: frameSize, height: frameSize)
                .modifier(OptionalGlassBackgroundModifier(style: buttonBackground, theme: theme))
                .contentShape(buttonBackground.glassStyle != nil ? AnyShape(Circle()) : AnyShape(Rectangle()))
                .symbolEffect(.rotate.byLayer, options: .speed(2).nonRepeating, value: seekTapCount)
        }
    }

    // MARK: - Auto-Play Next Button

    @ViewBuilder
    private var autoPlayNextButton: some View {
        if actions.onToggleAutoPlayNext != nil {
            controlButton(
                systemImage: "play.square.stack.fill",
                tint: actions.isAutoPlayNextEnabled ? .red : .white
            ) {
                actions.onToggleAutoPlayNext?()
            }
        }
    }
}

// MARK: - Optional Glass Background Modifier

/// A view modifier that conditionally applies a glass background based on the button background style.
private struct OptionalGlassBackgroundModifier: ViewModifier {
    let style: ButtonBackgroundStyle
    var theme: ControlsTheme = .dark

    func body(content: Content) -> some View {
        if let glassStyle = style.glassStyle {
            content.glassBackground(glassStyle, in: .circle, fallback: .ultraThinMaterial, colorScheme: theme.colorScheme)
        } else {
            content
        }
    }
}

/// A view modifier that conditionally applies a capsule glass background based on the button background style.
private struct OptionalCapsuleGlassBackgroundModifier: ViewModifier {
    let style: ButtonBackgroundStyle
    var theme: ControlsTheme = .dark

    func body(content: Content) -> some View {
        if let glassStyle = style.glassStyle {
            content.glassBackground(glassStyle, in: .capsule, fallback: .ultraThinMaterial, colorScheme: theme.colorScheme)
        } else {
            content
        }
    }
}

#endif
