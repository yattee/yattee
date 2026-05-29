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
    /// Tapping the avatar / title / author in the top bar toggles the video details panel.
    var onTitleTap: (() -> Void)? = nil
    /// Whether the floating video details panel is currently visible. When it opens,
    /// the controls hide immediately instead of waiting for the auto-hide timer.
    var isDetailsPanelVisible: Bool = false

    // MARK: - State

    @State private var isHovering = false
    @State private var hideTimer: Timer?
    @State private var isInteracting = false
    @State private var showControls: Bool?
    @State private var keyboardMonitor: Any?

    /// Extra top inset for the top bar so its content drops below the window's
    /// traffic-light buttons in the separate/floating window presentation, while
    /// keeping the avatar/title aligned to the leading edge.
    /// Stays 0 when there is no overlap (inline sheet, side panel, fullscreen).
    @State private var trafficLightInset: CGFloat = 0

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

    /// Yattee Server URL used by `ChannelAvatarView` for avatar fallback.
    private var yatteeServerURL: URL? {
        appEnvironment?.instancesManager.yatteeServerInstances.first { $0.isEnabled }?.url
    }

    // MARK: - Top Bar

    /// Top row showing channel avatar, video title, author name, and a close button.
    /// Mirrors the tvOS `topBar`, scaled down for macOS.
    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            if let video = playerState.currentVideo {
                Button {
                    onTitleTap?()
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        ChannelAvatarView(
                            author: video.author,
                            size: 36,
                            yatteeServerURL: yatteeServerURL,
                            source: video.id.source
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(video.title)
                                .font(.headline)
                                .lineLimit(1)
                                .foregroundStyle(.white)
                            Text(video.author.name)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onTitleTap == nil)
                .help(Text("player.controls.info"))
            }

            Spacer(minLength: 12)

            if onClose != nil {
                Button {
                    onClose?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("player.controls.close"))
            }
        }
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

                // Top bar (title/author/avatar/close) + control bar at bottom center
                VStack(spacing: 0) {
                    topBar

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
                        onPlayPrevious: onPlayPrevious,
                        onVolumeChanged: onVolumeChanged,
                        onMuteToggled: onMuteToggled,
                        onShowSettings: onShowSettings,
                        onShowQueue: onShowQueue,
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
                    .padding(.bottom, 20)
                }
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
