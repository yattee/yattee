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
    var onPlayPrevious: (() async -> Void)? = nil
    var onVolumeChanged: ((Float) -> Void)? = nil
    var onMuteToggled: (() -> Void)? = nil
    var onShowSettings: (() -> Void)? = nil
    var onShowQueue: (() -> Void)? = nil
    var onShowPlaylistSelector: (() -> Void)? = nil
    /// Tapping the avatar / title / author in the top bar toggles the video details panel.
    var onTitleTap: (() -> Void)? = nil
    /// Whether the floating video details panel is currently visible. When it opens,
    /// the controls hide immediately instead of waiting for the auto-hide timer.
    var isDetailsPanelVisible: Bool = false
    /// Change playback rate (used by the playback speed button).
    var onRateChanged: ((PlaybackRate) -> Void)? = nil

    // MARK: - State

    @State private var isHovering = false
    @State private var hideTimer: Timer?
    @State private var isInteracting = false
    @State private var showControls: Bool?
    @State private var keyboardMonitor: Any?
    /// Last pointer location from `.onContinuousHover`, used to tell real mouse
    /// movement apart from re-emitted hover events (e.g. after the view resizes
    /// when entering fullscreen).
    @State private var lastHoverLocation: CGPoint?
    /// Pointer rests on the top bar / bottom control bar — the idle timer must
    /// not hide the controls out from under it. Two flags because moving
    /// between the bars fires one bar's exit and the other's entry in
    /// unspecified order.
    @State private var isHoveringTopBar = false
    @State private var isHoveringBottomBar = false

    /// Window hosting these controls; keyboard shortcuts only apply to events
    /// destined for this window (not e.g. the Settings window).
    @State private var hostWindow: NSWindow?

    /// The active player controls layout (macOS preset). `nil` until loaded, so
    /// the bars don't flash a wrong default before the preset arrives.
    @State private var layout: PlayerControlsLayout?

    /// Extra top inset for the top bar so its content drops below the window's
    /// traffic-light buttons in the separate/floating window presentation, while
    /// keeping the avatar/title aligned to the leading edge.
    /// Stays 0 when there is no overlap (inline sheet, side panel, fullscreen).
    @State private var trafficLightInset: CGFloat = 0

    // MARK: - Control Bar Drag State

    /// Committed offset of the control bar from its default bottom-center
    /// position, as fractions of the container size so it survives window and
    /// aspect-ratio driven resizes. Mirrors SettingsManager; (0, 0) = docked.
    @State private var barOffsetFraction: CGSize = .zero
    /// Live drag translation in points; nil when not dragging.
    @State private var barDragTranslation: CGSize?
    /// Pixel offset captured at drag start so the drag composes with the committed offset.
    @State private var barDragBase: CGSize = .zero
    /// Measured size of the visible glass capsule (narrower than its 650pt layout frame).
    @State private var barSize = CGSize(width: 500, height: 90)
    /// Measured height of the top bar (including its gradient padding) so the
    /// dragged control bar can't overlap the top row of buttons.
    @State private var topBarHeight: CGFloat = 0

    private enum BarDrag {
        static let edgeMargin: CGFloat = 12
        static let snapDistance: CGFloat = 28
        static let bottomPadding: CGFloat = 20
    }

    // MARK: - Computed Properties

    /// Controls visibility - show when hovering, interacting, or paused
    private var shouldShowControls: Bool {
        // Ended/failed overlays take over the surface; controls stay hidden
        // regardless of hover or manual toggles.
        if playerState.playbackState == .ended || playerState.isFailed {
            return false
        }
        if let showControls {
            return showControls
        }
        // Show if hovering, interacting (scrubbing, adjusting volume), or paused
        if isHovering || isInteracting {
            return true
        }
        // Show when paused or loading
        return playerState.playbackState == .paused ||
               playerState.playbackState == .loading
    }

    /// Traffic-light visibility. Follows the controls, except on the
    /// ended/failed overlays: those hide the controls entirely (no hover
    /// brings them back), so the window buttons must stay up or the error /
    /// replay screen can't be closed.
    private var shouldShowTrafficLights: Bool {
        shouldShowControls || playerState.playbackState == .ended || playerState.isFailed
    }

    /// Whether the hosting window is in native fullscreen. The `isFullscreen`
    /// parameter covers the sheet-overlay flow, but its key-window half isn't
    /// reactive — check the tracked host window directly as well.
    private var isInNativeFullscreen: Bool {
        isFullscreen || hostWindow?.styleMask.contains(.fullScreen) == true
    }

    /// Yattee Server URL used by `ChannelAvatarView` for avatar fallback.
    private var yatteeServerURL: URL? {
        appEnvironment?.instancesManager.yatteeServerInstances.first { $0.isEnabled }?.url
    }

    // MARK: - Top Bar

    /// Top row rendered from the active preset's top section (title/author,
    /// keep-on-top pin, close by default).
    private func topBar(layout: PlayerControlsLayout) -> some View {
        MacOSControlsSectionRenderer(
            section: layout.topSection,
            actions: controlsActions(layout: layout),
            globalSettings: layout.globalSettings,
            context: .overlay
        )
        .padding(.horizontal, 20)
        .padding(.top, 16 + trafficLightInset)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.55), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
        .background(
            TrafficLightInsetReader(inset: $trafficLightInset)
                .allowsHitTesting(false)
        )
    }

    // MARK: - Actions

    /// Consolidated actions for the section renderers.
    private func controlsActions(layout: PlayerControlsLayout) -> PlayerControlsActions {
        PlayerControlsActions(
            playerState: playerState,
            isWideScreenLayout: true,
            isFullscreen: isFullscreen,
            isWidescreenVideo: true,
            isPanelVisible: isDetailsPanelVisible,
            panelSide: .right,
            showVolumeControls: layout.globalSettings.volumeMode == .mpv,
            showDebugButton: true,
            showCloseButton: onClose != nil,
            currentVideo: playerState.currentVideo,
            availableCaptions: [],
            currentCaption: nil,
            availableStreams: [],
            currentStream: nil,
            currentAudioStream: nil,
            isAutoPlayNextEnabled: appEnvironment?.settingsManager.queueAutoPlayNext ?? true,
            yatteeServerURL: yatteeServerURL,
            deArrowBrandingProvider: appEnvironment?.deArrowBrandingProvider,
            onClose: onClose,
            onToggleDebug: { [self] in
                withAnimation(.easeInOut(duration: 0.2)) {
                    playerState.showDebugOverlay.toggle()
                }
            },
            onTogglePiP: onTogglePiP,
            onToggleFullscreen: onToggleFullscreen,
            onToggleDetailsVisibility: onTitleTap,
            onToggleAutoPlayNext: { [weak appEnvironment] in
                appEnvironment?.settingsManager.queueAutoPlayNext.toggle()
            },
            onShowSettings: onShowSettings,
            onPlayNext: onPlayNext,
            onPlayPrevious: onPlayPrevious,
            onPlayPause: { [self] in
                let wasPaused = playerState.playbackState == .paused
                onPlayPause()
                showControls = true
                if wasPaused {
                    resetHideTimer()
                }
            },
            onSeekForward: { seconds in await onSeekForward(seconds) },
            onSeekBackward: { seconds in await onSeekBackward(seconds) },
            onVolumeChanged: onVolumeChanged,
            onMuteToggled: onMuteToggled,
            onCancelHideTimer: { [self] in cancelHideTimer() },
            onResetHideTimer: { [self] in resetHideTimer() },
            onSliderAdjustmentChanged: { [self] adjusting in
                isInteracting = adjusting
                if adjusting {
                    cancelHideTimer()
                } else {
                    resetHideTimer()
                }
            },
            onRateChanged: onRateChanged,
            onShowPlaylistSelector: onShowPlaylistSelector,
            onShowQueue: onShowQueue,
            onControlsLockToggled: { [self] locked in
                playerState.isControlsLocked = locked
            }
        )
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

                // Top bar (from preset top section) + control bar at bottom center
                if let layout {
                    VStack(spacing: 0) {
                        topBar(layout: layout)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topBarHeight = $0 }
                            .onHover { hovering in
                                isHoveringTopBar = hovering
                                if !hovering { startHideTimer() }
                            }

                        Spacer()

                        MacOSControlBar(
                            playerState: playerState,
                            section: layout.bottomSection,
                            globalSettings: layout.globalSettings,
                            actions: controlsActions(layout: layout),
                            onSeek: onSeek,
                            showChapters: layout.progressBarSettings.showChapters,
                            sponsorSegments: playerState.sponsorSegments,
                            sponsorBlockSettings: layout.progressBarSettings.sponsorBlockSettings,
                            playedColor: layout.progressBarSettings.playedColor.color,
                            onInteractionStarted: {
                                isInteracting = true
                                cancelHideTimer()
                            },
                            onInteractionEnded: {
                                isInteracting = false
                                resetHideTimer()
                            }
                        )
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { barSize = $0 }
                        .onHover { hovering in
                            isHoveringBottomBar = hovering
                            if !hovering { startHideTimer() }
                        }
                        // The player window is movable by background; without this,
                        // AppKit claims drags on the glass capsule as window moves
                        // and the reposition gesture never fires.
                        .background(WindowDragBlockingView())
                        .frame(width: 650)
                        .padding(.bottom, BarDrag.bottomPadding)
                        .offset(barOffset(in: geometry.size))
                        .gesture(barDragGesture(in: geometry.size))
                        .animation(
                            .spring(response: 0.3, dampingFraction: 0.75),
                            value: barOffset(in: geometry.size) == .zero
                        )
                    }
                    .opacity(shouldShowControls ? 1 : 0)
                    .allowsHitTesting(shouldShowControls)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(
            HostWindowReader(window: $hostWindow)
                .allowsHitTesting(false)
        )
        .animation(.easeInOut(duration: 0.2), value: shouldShowControls)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                isHovering = true
                // Only genuine movement counts: the first event after a gap
                // (pointer entry, fullscreen resize re-emission) is a baseline,
                // so entering fullscreen doesn't itself pop the controls up.
                let moved = lastHoverLocation.map {
                    hypot($0.x - location.x, $0.y - location.y) > 1
                } ?? false
                lastHoverLocation = location
                guard moved else { break }
                // Mouse movement clears a hide override (left by the idle
                // timer or a manual toggle) so controls show again. Not while
                // the details panel is open — that state keeps controls
                // hidden on purpose.
                if showControls == false && !isDetailsPanelVisible {
                    showControls = nil
                }
                resetHideTimer()
            case .ended:
                isHovering = false
                lastHoverLocation = nil
                startHideTimer()
            }
        }
        .onChange(of: isFullscreen) { _, _ in
            // The fullscreen transition resizes the view and re-emits hover
            // with jumped coordinates — rebaseline so that doesn't read as
            // mouse movement.
            lastHoverLocation = nil
        }
        .onChange(of: isDetailsPanelVisible) { _, isVisible in
            if isVisible {
                // Hide controls immediately when the details panel opens.
                showControls = false
                cancelHideTimer()
            } else {
                // Restore default hover/paused-driven visibility when it closes.
                showControls = nil
            }
        }
        .onChange(of: shouldShowControls) { _, visible in
            // Hidden bars stop hit-testing, so their `onHover(false)` may
            // never arrive — clear the flags or they'd stay stuck true and
            // block every future idle-hide.
            if !visible {
                isHoveringTopBar = false
                isHoveringBottomBar = false
            }
        }
        .onChange(of: shouldShowTrafficLights) { _, visible in
            setTrafficLightsVisible(visible)
        }
        .onChange(of: hostWindow) { oldWindow, _ in
            // Restore the old window's chrome when re-parented (sheet <->
            // floating window), then sync the new window to the current state.
            if let oldWindow { applyTrafficLightAlpha(1, to: oldWindow, animated: false) }
            setTrafficLightsVisible(shouldShowTrafficLights, animated: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { note in
            // In fullscreen the system owns titlebar visibility (hover at the
            // top edge reveals it) — hand the buttons back at full alpha.
            if let window = note.object as? NSWindow, window === hostWindow {
                applyTrafficLightAlpha(1, to: window, animated: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            if let window = note.object as? NSWindow, window === hostWindow {
                setTrafficLightsVisible(shouldShowTrafficLights, animated: false)
                // Pointer hiding is a fullscreen-only behavior; make sure it's
                // back even before the next mouse move.
                NSCursor.setHiddenUntilMouseMoves(false)
            }
        }
        .onChange(of: playerState.playbackState) { oldState, newState in
            // When playback starts, start hide timer
            if newState == .playing && shouldShowControls {
                startHideTimer()
            }
            // A new load resets any manual show/hide override (e.g. hidden
            // after ended/failed) so controls are visible while loading.
            if newState == .loading {
                showControls = nil
            }
            // Ended/failed hide via shouldShowControls; just stop the timer.
            if newState == .ended || playerState.isFailed {
                cancelHideTimer()
            }
        }
        .onAppear {
            setupKeyboardMonitor()
            if let settings = appEnvironment?.settingsManager {
                barOffsetFraction = CGSize(
                    width: settings.macControlsBarOffsetX,
                    height: settings.macControlsBarOffsetY
                )
            }
        }
        .onDisappear {
            removeKeyboardMonitor()
            // The controls unmount while the window stays up (PiP, debug
            // overlay) — don't leave the window without its close button.
            if let hostWindow { applyTrafficLightAlpha(1, to: hostWindow, animated: false) }
        }
        .task {
            await loadLayout()
        }
        .onReceive(NotificationCenter.default.publisher(for: .playerControlsActivePresetDidChange)) { _ in
            Task { await loadLayout() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .playerControlsPresetsDidChange)) { _ in
            Task { await loadLayout() }
        }
        // The ended/failed overlays own the surface — their replay/retry/next
        // buttons live in the layer BELOW this view. The inner layers already
        // opt out of hit-testing in those states, but on macOS 15 the hover
        // tracking on this view makes its full frame participate in click
        // hit-testing anyway, silently swallowing every click aimed at those
        // buttons. Drop the whole view out of hit-testing while they're up.
        .allowsHitTesting(playerState.playbackState != .ended && !playerState.isFailed)
    }

    // MARK: - Control Bar Drag

    /// Display offset of the control bar for the current container size:
    /// live drag translation when dragging, otherwise the committed fraction,
    /// clamped so the capsule stays visible, with magnetic snap to default.
    private func barOffset(in container: CGSize) -> CGSize {
        let raw: CGSize
        if let drag = barDragTranslation {
            raw = CGSize(
                width: barDragBase.width + drag.width,
                height: barDragBase.height + drag.height
            )
        } else {
            raw = CGSize(
                width: barOffsetFraction.width * container.width,
                height: barOffsetFraction.height * container.height
            )
        }
        let clamped = clampBarOffset(raw, in: container)
        if hypot(clamped.width, clamped.height) < BarDrag.snapDistance {
            return .zero
        }
        return clamped
    }

    /// Clamps an offset so the visible capsule (measured `barSize`, not the
    /// wider layout frame) keeps at least `edgeMargin` from every container edge
    /// and never overlaps the top bar's button row.
    private func clampBarOffset(_ offset: CGSize, in container: CGSize) -> CGSize {
        let maxDX = max(0, (container.width - barSize.width) / 2 - BarDrag.edgeMargin)
        let topInset = max(topBarHeight, BarDrag.edgeMargin)
        let travelUp = max(0, container.height - BarDrag.bottomPadding - barSize.height - topInset)
        let travelDown = max(0, BarDrag.bottomPadding - BarDrag.edgeMargin)
        return CGSize(
            width: min(max(offset.width, -maxDX), maxDX),
            height: min(max(offset.height, -travelUp), travelDown)
        )
    }

    private func barDragGesture(in container: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                guard !playerState.isControlsLocked else { return }
                if barDragTranslation == nil {
                    barDragBase = barOffset(in: container)
                    isInteracting = true
                    cancelHideTimer()
                }
                barDragTranslation = value.translation
            }
            .onEnded { value in
                guard barDragTranslation != nil else { return }
                let final = clampBarOffset(
                    CGSize(
                        width: barDragBase.width + value.translation.width,
                        height: barDragBase.height + value.translation.height
                    ),
                    in: container
                )
                let docked = hypot(final.width, final.height) < BarDrag.snapDistance
                let committed = docked ? .zero : final
                barOffsetFraction = CGSize(
                    width: committed.width / max(1, container.width),
                    height: committed.height / max(1, container.height)
                )
                barDragTranslation = nil
                isInteracting = false
                resetHideTimer()
                if let settings = appEnvironment?.settingsManager {
                    settings.macControlsBarOffsetX = barOffsetFraction.width
                    settings.macControlsBarOffsetY = barOffsetFraction.height
                }
            }
    }

    // MARK: - Traffic Lights

    /// Fades the hosting window's traffic-light buttons together with the
    /// controls overlay, QuickTime-style. Only applies to the dedicated
    /// separate player window — the inline sheet's parent window keeps its own
    /// chrome — and never in fullscreen, where the system owns the titlebar.
    private func setTrafficLightsVisible(_ visible: Bool, animated: Bool = true) {
        guard let window = hostWindow,
              window === ExpandedPlayerWindowManager.shared.currentPlayerWindow,
              !window.styleMask.contains(.fullScreen) else { return }
        applyTrafficLightAlpha(visible ? 1 : 0, to: window, animated: animated)
    }

    private func applyTrafficLightAlpha(_ alpha: CGFloat, to window: NSWindow, animated: Bool) {
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let views = buttons.compactMap { window.standardWindowButton($0) }
        guard !views.isEmpty else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                views.forEach { $0.animator().alphaValue = alpha }
            }
        } else {
            views.forEach { $0.alphaValue = alpha }
        }
    }

    // MARK: - Layout Loading

    private func loadLayout() async {
        guard let service = appEnvironment?.playerControlsLayoutService else { return }
        layout = await service.activeLayout()
    }

    // MARK: - Keyboard Shortcuts

    private func setupKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Only handle keys destined for the window hosting the player;
            // pass through events for other windows (e.g. Settings).
            guard let window = event.window, window === hostWindow else { return event }

            // Let text fields receive typing (the field editor is an NSText).
            if window.firstResponder is NSText { return event }

            // When controls are locked, ignore playback keys (space/arrows/mute) and
            // only keep fullscreen (F) and exit-fullscreen (Esc) working.
            if playerState.isControlsLocked {
                switch event.keyCode {
                case 3: // F
                    onToggleFullscreen?()
                    return nil
                case 53: // Escape
                    if isFullscreen {
                        onToggleFullscreen?()
                        return nil
                    }
                    return event
                default:
                    return event // Pass through space/arrows/M while locked
                }
            }

            // Let ⌘-based key equivalents reach the menu bar (Playback menu shortcuts
            // like ⌘←/⌘⇧← seek and ⌘⌥← previous video) instead of consuming them here.
            if event.modifierFlags.contains(.command) { return event }

            let isShiftHeld = event.modifierFlags.contains(.shift)

            // Handle keyboard shortcuts
            switch event.keyCode {
            case 49: // Space
                onPlayPause()
                return nil // Consume event

            case 123: // Left arrow
                let seconds = TimeInterval(
                    isShiftHeld
                        ? layout?.centerSettings.secondarySeekBackwardSeconds ?? 30
                        : layout?.centerSettings.seekBackwardSeconds ?? 10
                )
                Task { await onSeekBackward(seconds) }
                return nil

            case 124: // Right arrow
                let seconds = TimeInterval(
                    isShiftHeld
                        ? layout?.centerSettings.secondarySeekForwardSeconds ?? 30
                        : layout?.centerSettings.seekForwardSeconds ?? 10
                )
                Task { await onSeekForward(seconds) }
                return nil

            case 126: // Up arrow
                // In system volume mode MPV volume is pinned at 1.0; don't fight it.
                guard layout?.globalSettings.volumeMode != .system else { return event }
                let newVolume = min(1.0, playerState.volume + 0.1)
                playerState.volume = newVolume
                onVolumeChanged?(newVolume)
                return nil

            case 125: // Down arrow
                guard layout?.globalSettings.volumeMode != .system else { return event }
                let newVolume = max(0, playerState.volume - 0.1)
                playerState.volume = newVolume
                onVolumeChanged?(newVolume)
                return nil

            case 46: // M key
                guard layout?.globalSettings.volumeMode != .system else { return event }
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
        } else if isInNativeFullscreen {
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    private func startHideTimer() {
        cancelHideTimer()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            Task { @MainActor in
                // Idle-based hide: the pointer resting over the video doesn't
                // keep controls up (it never leaves the view in fullscreen) —
                // only resting on one of the bars does.
                if playerState.playbackState == .playing && !isInteracting
                    && !isHoveringTopBar && !isHoveringBottomBar {
                    showControls = false
                    if isInNativeFullscreen {
                        NSCursor.setHiddenUntilMouseMoves(true)
                    }
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

// MARK: - Window Drag Blocking View

/// Blocks `isMovableByWindowBackground` window-dragging within its bounds so
/// drags on the control bar reach the SwiftUI reposition gesture instead of
/// moving the player window. Doesn't handle any events itself — unhandled
/// mouse events continue up the responder chain to the hosting view.
private struct WindowDragBlockingView: NSViewRepresentable {
    final class BlockingNSView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }

    func makeNSView(context: Context) -> BlockingNSView { BlockingNSView() }
    func updateNSView(_ nsView: BlockingNSView, context: Context) {}
}

// MARK: - Host Window Reader

/// Reports the `NSWindow` hosting this view so the keyboard monitor can ignore
/// events destined for other windows. Tracks re-parenting (mini bar <-> sheet
/// <-> floating window) via `viewDidMoveToWindow`.
private struct HostWindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onWindowChange = { newWindow in
            if window !== newWindow { window = newWindow }
        }
        return view
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        nsView.onWindowChange = { newWindow in
            if window !== newWindow { window = newWindow }
        }
    }

    final class ReaderView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let window = window
            DispatchQueue.main.async { [weak self] in
                self?.onWindowChange?(window)
            }
        }
    }
}

// MARK: - Traffic Light Inset Reader

/// Reports how far the top bar's leading content must be pushed to clear the
/// hosting window's traffic-light buttons (close/minimize/zoom).
///
/// Returns 0 whenever the buttons don't actually overlap this view — e.g. in
/// fullscreen (buttons hidden), or when the controls render inside the inline
/// sheet / side panel where the top bar sits below the window's titlebar.
private struct TrafficLightInsetReader: NSViewRepresentable {
    @Binding var inset: CGFloat

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onUpdate = { newInset in
            if inset != newInset { inset = newInset }
        }
        return view
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        nsView.onUpdate = { newInset in
            if inset != newInset { inset = newInset }
        }
        DispatchQueue.main.async { nsView.recompute() }
    }

    final class ReaderView: NSView {
        var onUpdate: ((CGFloat) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObservers()
            postsFrameChangedNotifications = true

            guard let window else {
                onUpdate?(0)
                return
            }

            let center = NotificationCenter.default
            let names: [NSNotification.Name] = [
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification,
                NSWindow.didResizeNotification,
                NSWindow.didBecomeKeyNotification
            ]
            for name in names {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.recompute()
                })
            }
            observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: self, queue: .main) { [weak self] _ in
                self?.recompute()
            })

            recompute()
        }

        func recompute() {
            guard let window,
                  !window.styleMask.contains(.fullScreen) else {
                onUpdate?(0)
                return
            }

            let buttons = [
                window.standardWindowButton(.closeButton),
                window.standardWindowButton(.miniaturizeButton),
                window.standardWindowButton(.zoomButton)
            ].compactMap { $0 }.filter { !$0.isHidden && $0.superview != nil }

            guard !buttons.isEmpty else {
                onUpdate?(0)
                return
            }

            // Union of the traffic lights and this view, both in window base coords.
            let buttonsRect = buttons
                .map { $0.convert($0.bounds, to: nil) }
                .reduce(NSRect.null) { $0.union($1) }
            let selfRect = convert(bounds, to: nil)

            // Only inset when the buttons actually sit over this view.
            guard selfRect.intersects(buttonsRect) else {
                onUpdate?(0)
                return
            }

            // Window base coords have a bottom-left origin (Y grows upward), so the
            // buttons' bottom edge is `buttonsRect.minY` and this view's top edge is
            // `selfRect.maxY`. Drop the content from its top edge down to just below
            // the buttons, keeping it aligned to the leading edge.
            let overlap = selfRect.maxY - buttonsRect.minY
            onUpdate?(max(0, overlap + 8))
        }

        private func removeObservers() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
        }

        deinit {
            removeObservers()
        }
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
