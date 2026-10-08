//
//  ExpandedPlayerWindowManager.swift
//  Yattee
//
//  Manages expanded player window on macOS.
//  Uses a separate NSWindow for better control over presentation and floating behavior.
//

#if os(macOS)
import AppKit
import SwiftUI

/// Manages the expanded player window on macOS.
/// Supports both normal window and floating (always-on-top) modes.
@MainActor
final class ExpandedPlayerWindowManager: NSObject {
    static let shared = ExpandedPlayerWindowManager()

    private var playerWindow: NSWindow?
    private weak var appEnvironment: AppEnvironment?

    /// Main app window hosting the inline player overlay, the observers that
    /// mirror its fullscreen transitions into the coordinator flag (Esc, green
    /// button, menu, Mission Control all bypass the player's own button), the
    /// toolbar visibility to restore when the overlay ends (the toolbar is
    /// hidden while the overlay is up so it doesn't sit above the video), and
    /// whether the window was already fullscreen before the overlay began (so
    /// collapsing doesn't exit a fullscreen the user had independently).
    private weak var overlayParent: NSWindow?
    private var overlayWindowObservers: [NSObjectProtocol] = []
    private var overlayToolbarWasVisible: Bool?
    private var overlayWasFullScreenAtBegin = false
    private var isOverlayParentEnteringFullScreen = false

    /// The main window belongs to the app rather than the player. Preserve its
    /// normal sizing rules while the inline overlay temporarily owns resizing.
    private struct WindowSizingConstraints {
        let contentAspectRatio: NSSize
        let contentResizeIncrements: NSSize
        let contentMinSize: NSSize
        let minSize: NSSize
    }
    private var overlaySizingConstraints: WindowSizingConstraints?

    /// Window hosting ContentView, registered by `MainContentWindowReader`.
    /// `beginInlineOverlay` must not guess via mainWindow/keyWindow: when the
    /// separate-window setting is toggled during playback, the key window is
    /// the Settings window (and the separate player window can be "main"), so
    /// guessing hides/restores the toolbar on the wrong window.
    private weak var mainContentWindow: NSWindow?

    /// Registers the window hosting the app's main content view.
    func registerMainContentWindow(_ window: NSWindow?) {
        guard let window else { return }
        mainContentWindow = window
    }

    /// Whether the window has performed its first size application since being
    /// shown. The first resize after each open snaps (no animation) so the player
    /// appears at its final fixed layout; later resizes (e.g. switching to a
    /// different-aspect video while the window stays open) animate normally.
    private var hasCompletedInitialSizing = false

    /// Aspect ratio received while the window was in native fullscreen. Applying
    /// `contentAspectRatio`/`setFrame` to a fullscreen window makes AppKit fit and
    /// center the content inside the fullscreen space (black bars), so the ratio
    /// is parked here and replayed in `windowDidExitFullScreen`.
    private var pendingFullScreenAspectRatio: Double?

    /// True between `windowWillEnterFullScreen` and `windowDidEnterFullScreen`
    /// on the separate player window. The style mask may not carry
    /// `.fullScreen` yet at will-enter time, and the corner panels hide right
    /// then (which re-locks the aspect ratio) — the lock must park instead of
    /// touching a window mid-transition.
    private var isPlayerWindowEnteringFullScreen = false

    /// Corner layout panels hidden by entering native fullscreen so the video
    /// alone fills the screen; restored when fullscreen ends.
    private var cornerPanelsHiddenForFullScreen = false

    private var activePlayerWindow: NSWindow? {
        playerWindow ?? overlayParent
    }

    private var isActivePlayerWindowFullScreen: Bool {
        if let playerWindow {
            return isPlayerWindowEnteringFullScreen || playerWindow.styleMask.contains(.fullScreen)
        }
        return isOverlayParentEnteringFullScreen || (overlayParent?.styleMask.contains(.fullScreen) ?? false)
    }

    // Configuration
    private static let minWidth: CGFloat = 640
    private static let minHeight: CGFloat = 360
    private static let maxScreenRatio: CGFloat = 0.7
    private static let targetVideoHeight: CGFloat = 720
    private static let defaultAspectRatio: Double = 16.0 / 9.0
    private static let frameAutosaveName = "ExpandedPlayerWindow"

    /// Aspect-lock change requested while the user is dragging the window.
    /// Changing `contentAspectRatio`/`contentResizeIncrements` mid-drag makes
    /// AppKit's resize handler switch modes under the cursor and snap the
    /// frame, so the change is parked here and applied in
    /// `windowDidEndLiveResize`. The last request wins.
    private enum PendingAspectLock { case lock(Double), unlock }
    private var pendingLiveResizeAspectLock: PendingAspectLock?

    /// Whether the user is currently dragging the active player host window.
    var isLiveResizing: Bool {
        activePlayerWindow?.inLiveResize == true
    }

    var isPresented: Bool {
        playerWindow != nil
    }

    /// The live player window managed by this instance (nil after hide()).
    /// A window that exists here but isn't visible is mid-presentation or
    /// hidden for PiP — both valid homes for the shared render view, unlike a
    /// stale ordered-out window that is no longer tracked. Used by
    /// MPVContainerNSView when picking a transfer target.
    var currentPlayerWindow: NSWindow? {
        playerWindow
    }

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Shows the expanded player in a separate window.
    /// - Parameters:
    ///   - appEnvironment: The app environment for state and services
    ///   - animated: Whether to animate the window appearance
    func show(with appEnvironment: AppEnvironment, animated: Bool = true) {
        // If window already exists (hidden for PiP), restore it instead of creating new one
        if let existingWindow = playerWindow {
            // Already on screen (e.g. "Play Now" while playing) — just bring it
            // forward; resetting alphaValue here would make the window blink.
            if existingWindow.isVisible {
                LoggingService.shared.debug("ExpandedPlayerWindowManager: show() - window already visible, bringing to front", category: .player)
                existingWindow.makeKeyAndOrderFront(nil)
                return
            }
            LoggingService.shared.debug("ExpandedPlayerWindowManager: show() - restoring existing window (was hidden for PiP)", category: .player)
            if animated {
                existingWindow.alphaValue = 0
                existingWindow.makeKeyAndOrderFront(nil)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    existingWindow.animator().alphaValue = 1
                }
            } else {
                existingWindow.alphaValue = 1
                existingWindow.makeKeyAndOrderFront(nil)
            }
            // Any forced draw requested while the window was ordered out was
            // dropped (no drawable); the layer is pull-based, so repaint now
            // that the window is on screen — otherwise a paused video stays
            // black until the next MPV frame (never, while paused).
            (appEnvironment.playerService.currentBackend as? MPVBackend)?.resumeRendering()
            return
        }

        self.appEnvironment = appEnvironment

        // Mark expanding state for mini player coordination
        appEnvironment.navigationCoordinator.isPlayerExpanding = true

        // Whether the window should float above other windows (always on top).
        let floating = appEnvironment.settingsManager.macPlayerFloating

        // Host a lightweight two-phase root instead of ExpandedPlayerSheet directly.
        // AppKit won't composite the window to screen until the hosted SwiftUI view
        // finishes its first layout pass; ExpandedPlayerSheet is heavy (MPV setup,
        // full controls, layout math), so building it inline leaves the alpha 0→1
        // fade with nothing to draw and the window only pops in after the render.
        // ExpandedPlayerWindowRoot paints black + spinner immediately, then defers
        // building ExpandedPlayerSheet by one runloop so the window appears at once.
        let playerView = ExpandedPlayerWindowRoot()
            .appEnvironment(appEnvironment)

        // Open at the real video aspect ratio when it's already known (e.g.
        // expanding a video already playing in the mini bar) so the window appears
        // at its final size with no snap-jump. Falls back to 16:9 when the ratio
        // isn't decoded yet; the first-resize snap below removes any later grow.
        let knownAspect = appEnvironment.playerService.state.videoAspectRatio ?? 0
        let seedAspect = knownAspect > 0 ? knownAspect : Self.defaultAspectRatio

        // Create hosting controller
        let hostingController = NSHostingController(rootView: playerView)
        // Don't let the hosting controller drive the window size from the SwiftUI
        // content's fitting size. The lightweight loading root (just a spinner) has a
        // tiny ideal size, which would otherwise shrink the window and then grow it
        // when ExpandedPlayerSheet builds. Window sizing is owned by `initialSize`
        // below and `resizeToFitAspectRatio` once the real video ratio is known.
        hostingController.sizingOptions = []

        // Calculate initial window size at the seeded aspect ratio
        let initialSize = calculateInitialWindowSize(aspectRatio: seedAspect)

        // Create window with appropriate style
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Configure window appearance
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.contentViewController = hostingController

        // Lock manual resize to the video aspect ratio. Seeded with the real ratio
        // when known (else 16:9); updated as soon as the real ratio is known.
        // Corner layout with its panels visible (already active on a window
        // re-mount, e.g. switching from the inline overlay) keeps the window
        // unconstrained.
        if !appEnvironment.isCornerPanelLayoutActive {
            Self.applyAspectRatioConstraint(seedAspect, to: window)
        }

        // Force the intended size. Assigning `contentViewController` above resizes
        // the window to the hosting controller's fitting size — and the lightweight
        // loading root has a tiny fitting size, which produced a tiny window that
        // only grew once `resizeToFitAspectRatio` fired after streams loaded. Set
        // the content size back to `initialSize` so the window opens full-sized
        // during the loading phase too.
        window.setContentSize(initialSize)

        // Set up window delegate for close handling
        // Make ExpandedPlayerWindowManager itself the delegate to avoid lifecycle issues
        window.delegate = self

        // Configure window level based on the floating preference
        configureWindowLevel(window, floating: floating)

        // Center window on screen
        window.center()

        // With auto-resize off, the window must reopen exactly as the user last
        // left it — no fitting, no centering. Restore the persisted frame over
        // the computed default (no-op when nothing was saved yet, e.g. first
        // open). With auto-resize on, sizing is owned by resizeToFitAspectRatio.
        if !appEnvironment.settingsManager.playerSheetAutoResize {
            window.setFrameUsingName(Self.frameAutosaveName)
        }
        // Persist every later frame change (manual resize/move, auto-fit) so the
        // next open — with auto-resize off — can restore it.
        _ = window.setFrameAutosaveName(Self.frameAutosaveName)

        // Store reference
        self.playerWindow = window

        // Fresh window: the next resize is the initial sizing and must snap
        // (no animation) so the player appears at its final fixed layout.
        hasCompletedInitialSizing = false
        pendingFullScreenAspectRatio = nil

        // Show window
        if animated {
            window.alphaValue = 0
            window.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }, completionHandler: {
                Task { @MainActor in
                    appEnvironment.navigationCoordinator.isPlayerExpanding = false
                }
            })
        } else {
            window.makeKeyAndOrderFront(nil)
            appEnvironment.navigationCoordinator.isPlayerExpanding = false
        }
    }

    /// Hides and cleans up the player window.
    /// - Parameters:
    ///   - animated: Whether to animate the dismissal
    ///   - completion: Called after the window is hidden
    func hide(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard let window = playerWindow else {
            // No window means inline overlay mode (or the window is already
            // gone). The overlay's container may unmount without handing the
            // shared render view to the mini capsule in the same pass - watch
            // for the teardown to finish and re-home the view.
            MPVContainerNSView.scheduleSharedViewAdoptionRetry()
            completion?()
            return
        }

        // Mark collapsing state for mini player coordination
        appEnvironment?.navigationCoordinator.isPlayerCollapsing = true

        // Check if PiP is active - if so, just hide the window without destroying content
        // The AVSampleBufferDisplayLayer needs to stay alive while PiP is active
        let mpvBackend = appEnvironment?.playerService.currentBackend as? MPVBackend
        let isPiPActive = mpvBackend?.isPiPActive ?? false

        LoggingService.shared.debug("ExpandedPlayerWindowManager: hide() called, isPiPActive=\(isPiPActive)", category: .player)

        // Capture navigationCoordinator before closures to avoid Swift 6 concurrency warnings
        let navigationCoordinator = appEnvironment?.navigationCoordinator

        if isPiPActive {
            // PiP is active - just hide the window, keep content alive
            // Don't clear playerWindow reference so we can restore it later
            let hideWindow: @Sendable () -> Void = {
                Task { @MainActor in
                    navigationCoordinator?.isPlayerCollapsing = false
                    window.orderOut(nil)
                    completion?()
                }
            }

            exitFullScreenIfNeeded(window) {
                Task { @MainActor in
                    if animated {
                        NSAnimationContext.runAnimationGroup({ context in
                            context.duration = 0.2
                            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                            window.animator().alphaValue = 0
                        }, completionHandler: hideWindow)
                    } else {
                        hideWindow()
                    }
                }
            }
        } else {
            // PiP is not active - fully clean up the window
            // Clear reference immediately to prevent re-entry
            playerWindow = nil

            let cleanup: @Sendable () -> Void = {
                Task { @MainActor in
                    navigationCoordinator?.isPlayerCollapsing = false
                    window.delegate = nil
                    // Don't set contentViewController to nil or call close() - just order out
                    // This lets SwiftUI views deallocate naturally rather than being forcibly torn down
                    window.orderOut(nil)
                    // The mini capsule's claim on the shared render view was
                    // declined while this window was still visible during the
                    // fade-out, and nothing retries after orderOut - hand the
                    // view over now instead of leaving the capsule black until
                    // the render watchdog recovers it.
                    if MPVContainerNSView.recoverSharedPlayerViewIfNeeded() {
                        mpvBackend?.resumeRendering()
                    }
                    completion?()
                }
            }

            exitFullScreenIfNeeded(window) {
                Task { @MainActor in
                    if animated {
                        NSAnimationContext.runAnimationGroup({ context in
                            context.duration = 0.2
                            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                            window.animator().alphaValue = 0
                        }, completionHandler: cleanup)
                    } else {
                        cleanup()
                    }
                }
            }
        }
    }

    /// Runs `completion` once `window` is out of native fullscreen. Ordering
    /// out a fullscreen window skips the exit transition and strands its (now
    /// empty, black) fullscreen space on screen, so every dismissal path must
    /// leave fullscreen before hiding the window.
    private func exitFullScreenIfNeeded(_ window: NSWindow, completion: @escaping @Sendable () -> Void) {
        guard window.styleMask.contains(.fullScreen) else {
            completion()
            return
        }

        let waiter = FullScreenExitWaiter()
        waiter.observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: window,
            queue: .main
        ) { _ in
            waiter.finish(completion)
        }
        // Fallback: if AppKit refuses the exit (e.g. mid-transition), don't
        // leave the window stranded on screen forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            waiter.finish(completion)
        }
        window.toggleFullScreen(nil)
    }

    /// Updates the window level based on floating preference.
    /// Call this when the user changes the player mode setting.
    func updateWindowLevel(floating: Bool) {
        guard let window = playerWindow else { return }
        // Don't touch level/collectionBehavior mid-fullscreen; the setting is
        // re-read in windowDidExitFullScreen.
        guard !window.styleMask.contains(.fullScreen) else { return }
        configureWindowLevel(window, floating: floating)
    }

    /// Toggles native fullscreen on the player window.
    func toggleFullScreen() {
        guard let target = playerWindow ?? overlayParent else { return }

        // Entering fullscreen from the corner layout: hide the panels first
        // (the video grows over them inside the current window), and only
        // then run the fullscreen zoom — the reverse order zooms the whole
        // video-plus-panels arrangement and then reflows it on screen. The
        // entering flag is raised now so the aspect re-lock the panel hide
        // triggers parks instead of auto-fitting the window mid-way.
        if !target.styleMask.contains(.fullScreen) {
            if playerWindow != nil {
                isPlayerWindowEnteringFullScreen = true
            } else {
                isOverlayParentEnteringFullScreen = true
            }
            if hideCornerPanelsForFullScreen() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.cornerPanelHideDuration) { [weak self] in
                    self?.performNativeFullScreenToggle()
                }
                return
            }
        }
        performNativeFullScreenToggle()
    }

    /// Time the corner layout takes to animate its panels away (its
    /// `.easeInOut(duration: 0.25)` plus a beat for the last frame).
    private static var cornerPanelHideDuration: TimeInterval { 0.3 }

    private func performNativeFullScreenToggle() {
        guard let window = playerWindow else {
            // Inline overlay presentation: the player already fills the main
            // window, so fullscreen is just the window's native toggle. The
            // fullscreen observers keep the coordinator flag in sync.
            overlayParent?.toggleFullScreen(nil)
            return
        }
        // A floating (pinned) window carries .fullScreenAuxiliary, which AppKit
        // refuses to make a primary fullscreen window. Switch to the primary
        // config for the transition; windowDidExitFullScreen restores floating.
        if !window.styleMask.contains(.fullScreen) {
            configureWindowLevel(window, floating: false)
        }
        window.toggleFullScreen(nil)
    }

    // MARK: - Inline Overlay Presentation

    /// Called when the inline player overlay mounts in the main window
    /// (separate-window mode off, player expanded). Hides the main window's
    /// toolbar for the overlay's lifetime and starts mirroring the window's
    /// fullscreen state into `isMacInlinePlayerFullScreen`.
    func beginInlineOverlay() {
        guard overlayParent == nil else { return }
        guard let parent = mainContentWindow ?? NSApp.mainWindow ?? NSApp.keyWindow else {
            LoggingService.shared.debug(
                "ExpandedPlayerWindowManager: beginInlineOverlay found no main window",
                category: .player
            )
            return
        }

        LoggingService.shared.debug("ExpandedPlayerWindowManager: beginning inline overlay", category: .player)
        overlayParent = parent
        overlaySizingConstraints = WindowSizingConstraints(
            contentAspectRatio: parent.contentAspectRatio,
            contentResizeIncrements: parent.contentResizeIncrements,
            contentMinSize: parent.contentMinSize,
            minSize: parent.minSize
        )
        overlayToolbarWasVisible = parent.toolbar?.isVisible
        parent.toolbar?.isVisible = false
        overlayWasFullScreenAtBegin = parent.styleMask.contains(.fullScreen)
        isOverlayParentEnteringFullScreen = false
        hasCompletedInitialSizing = false
        pendingFullScreenAspectRatio = nil
        pendingLiveResizeAspectLock = nil

        let coordinator = AppEnvironment.shared.navigationCoordinator
        coordinator.isMacInlinePlayerFullScreen = overlayWasFullScreenAtBegin
        observeOverlayWindowTransitions(of: parent)

        // ExpandedPlayerSheet can appear before ContentView's onChange registers
        // the parent window. Re-run the same sizing decision on the next turn so
        // the inline presentation cannot miss its initial aspect setup.
        DispatchQueue.main.async { [weak self] in
            self?.synchronizeActiveWindowAspectRatio()
        }

        // The overlay's render container may mount while the mini capsule is
        // still tearing down, leaving the shared render view parked with no
        // later lifecycle event to re-trigger adoption — retry until it lands.
        MPVContainerNSView.scheduleSharedViewAdoptionRetry()
    }

    /// Called when the inline player overlay unmounts (collapse, close, or
    /// switch to separate-window mode). Restores the main window's toolbar and,
    /// if fullscreen was entered for the video, exits it.
    func endInlineOverlay() {
        guard let parent = overlayParent else { return }

        LoggingService.shared.debug("ExpandedPlayerWindowManager: ending inline overlay", category: .player)
        for observer in overlayWindowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        overlayWindowObservers = []

        // Leave the window fullscreen if the user was fullscreen before the
        // overlay began; only exit a fullscreen entered for the video.
        // The will-exit observer is already gone, so undo the fullscreen
        // panel hide here (the next player open re-derives the visibility
        // from the preset anyway).
        restoreCornerPanelsAfterFullScreen()
        if parent.styleMask.contains(.fullScreen), !overlayWasFullScreenAtBegin {
            parent.toggleFullScreen(nil)
        }
        if let wasVisible = overlayToolbarWasVisible {
            parent.toolbar?.isVisible = wasVisible
        }
        restoreOverlaySizingConstraints(on: parent)

        AppEnvironment.shared.navigationCoordinator.isMacInlinePlayerFullScreen = false
        overlayToolbarWasVisible = nil
        overlayWasFullScreenAtBegin = false
        isOverlayParentEnteringFullScreen = false
        pendingFullScreenAspectRatio = nil
        pendingLiveResizeAspectLock = nil
        overlayParent = nil
        overlaySizingConstraints = nil
    }

    /// Observes lifecycle events for the main window hosting the inline player.
    /// Fullscreen events keep the controls in sync, while closing the window
    /// must end playback just like closing the separate player window does.
    private func observeOverlayWindowTransitions(of parent: NSWindow) {
        for observer in overlayWindowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        let center = NotificationCenter.default
        overlayWindowObservers = [
            center.addObserver(
                forName: NSWindow.willEnterFullScreenNotification,
                object: parent,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    let manager = ExpandedPlayerWindowManager.shared
                    manager.isOverlayParentEnteringFullScreen = true
                    manager.hideCornerPanelsForFullScreen()
                }
            },
            center.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: parent,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    ExpandedPlayerWindowManager.shared.isOverlayParentEnteringFullScreen = false
                    AppEnvironment.shared.navigationCoordinator.isMacInlinePlayerFullScreen = true
                }
            },
            center.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: parent,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    let manager = ExpandedPlayerWindowManager.shared
                    manager.isOverlayParentEnteringFullScreen = false
                    AppEnvironment.shared.navigationCoordinator.isMacInlinePlayerFullScreen = false
                    // Mirror of the enter order: the window is back at its
                    // size first, then the panels slide in.
                    manager.restoreCornerPanelsAfterFullScreen()
                    if let window = manager.overlayParent {
                        manager.replayPendingFullScreenAspectRatio(on: window)
                    }
                }
            },
            center.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: parent,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    ExpandedPlayerWindowManager.shared.applyPendingLiveResizeAspectLock()
                }
            },
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: parent,
                queue: .main
            ) { notification in
                MainActor.assumeIsolated {
                    guard let window = notification.object as? NSWindow else { return }
                    ExpandedPlayerWindowManager.shared.handleInlineOverlayParentClose(window)
                }
            },
        ]
    }

    private func handleInlineOverlayParentClose(_ parent: NSWindow) {
        guard overlayParent === parent else { return }

        LoggingService.shared.debug(
            "ExpandedPlayerWindowManager: inline overlay parent closing, stopping playback",
            category: .player
        )

        let appEnvironment = AppEnvironment.shared
        appEnvironment.queueManager.clearQueue()
        appEnvironment.playerService.stop()

        // Remove the observer while the window is still alive, then unmount the
        // player. A normal inline collapse does not take this path and continues
        // playback in the mini player.
        endInlineOverlay()
        appEnvironment.navigationCoordinator.isPlayerExpanded = false
    }

    // MARK: - Corner Panels In Fullscreen

    /// Native fullscreen means "video only": the corner layout's panels hide
    /// for the fullscreen session (the layout animates them away and the
    /// video grows over them), and come back on exit if this hid them. The
    /// preset's remembered ("last visible") state is left untouched, so a
    /// fullscreen session doesn't change what the next player open shows.
    /// Returns whether this call hid the panels.
    @discardableResult
    func hideCornerPanelsForFullScreen() -> Bool {
        let appEnvironment = AppEnvironment.shared
        guard appEnvironment.navigationCoordinator.isCornerLayoutActive,
              appEnvironment.settingsManager.landscapeDetailsPanelVisible else { return false }
        cornerPanelsHiddenForFullScreen = true
        appEnvironment.settingsManager.landscapeDetailsPanelVisible = false
        LoggingService.shared.debug("ExpandedPlayerWindowManager: hid corner panels for fullscreen", category: .player)
        return true
    }

    /// Restores the panels hidden by `hideCornerPanelsForFullScreen`, unless
    /// the user showed them again while fullscreen (title tap) — then there is
    /// nothing to undo.
    func restoreCornerPanelsAfterFullScreen() {
        guard cornerPanelsHiddenForFullScreen else { return }
        cornerPanelsHiddenForFullScreen = false
        let appEnvironment = AppEnvironment.shared
        guard !appEnvironment.settingsManager.landscapeDetailsPanelVisible else { return }
        appEnvironment.settingsManager.landscapeDetailsPanelVisible = true
        LoggingService.shared.debug("ExpandedPlayerWindowManager: restored corner panels after fullscreen", category: .player)
    }

    /// Cleans up a window that was hidden for PiP when PiP ends without restoring.
    /// Call this when PiP is closed via the X button (not restore).
    func cleanupAfterPiP() {
        guard let window = playerWindow else { return }

        LoggingService.shared.debug("ExpandedPlayerWindowManager: cleanupAfterPiP called", category: .player)

        // Clear our reference immediately to prevent further use
        playerWindow = nil
        window.delegate = nil

        // Don't forcefully destroy the contentViewController or close the window immediately.
        // This causes crashes because AVKit's PiP implementation adds internal views to the
        // window hierarchy (via NSHostingController), and forcefully tearing down the view
        // hierarchy while AVKit still has references causes use-after-free crashes.
        //
        // Instead, just order the window out and let it deallocate naturally when all
        // references are released.
        window.orderOut(nil)

        LoggingService.shared.debug("ExpandedPlayerWindowManager: window ordered out", category: .player)
    }

    /// Resizes the player window to fit the given video aspect ratio.
    /// - Parameters:
    ///   - aspectRatio: Video width / height ratio
    ///   - animated: Whether to animate the resize
    func resizeToFitAspectRatio(_ aspectRatio: Double, animated: Bool = true) {
        guard let window = activePlayerWindow else { return }
        guard aspectRatio > 0 else { return }

        // In native fullscreen the video must keep the whole screen; constraining
        // or reframing the window here would letterbox the content inside the
        // fullscreen space. Park the ratio and replay it on fullscreen exit.
        if isActivePlayerWindowFullScreen {
            pendingFullScreenAspectRatio = aspectRatio
            LoggingService.shared.debug(
                "resizeToFitAspectRatio deferred while fullscreen aspect=\(aspectRatio)",
                category: .player
            )
            return
        }

        // Never reframe the window under the user's cursor. Auto-fit during a
        // live drag fights the drag (and, when the fitted size crosses the
        // corner-layout width threshold, oscillates between layouts every
        // frame). The user's drag owns the size; drop the fit and only keep
        // the aspect lock in sync (deferred to the end of the drag).
        if window.inLiveResize {
            lockAspectRatio(aspectRatio)
            return
        }

        // Always update the aspect-ratio lock, even if we end up not resizing here.
        Self.applyAspectRatioConstraint(aspectRatio, to: window)

        // Get screen bounds
        guard let screen = window.screen ?? NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        // Calculate target size
        let targetSize = calculateWindowSize(for: aspectRatio, screenFrame: screenFrame)

        // Calculate new frame centered on current position
        let currentFrame = window.frame
        let newOrigin = NSPoint(
            x: currentFrame.midX - targetSize.width / 2,
            y: currentFrame.midY - targetSize.height / 2
        )
        let newFrame = NSRect(origin: newOrigin, size: targetSize)

        // Ensure frame stays on screen
        let adjustedFrame = constrainToScreen(newFrame, screen: screen)

        // The first resize after each open snaps regardless of the requested
        // animation, so the player appears at its final fixed layout instead of
        // animating (the video/controls track the window's live size). Later
        // resizes — e.g. switching to a different-aspect video while the window
        // stays open — honor `animated`.
        let effectiveAnimated = animated && hasCompletedInitialSizing
        hasCompletedInitialSizing = true

        LoggingService.shared.debug(
            "resizeToFitAspectRatio aspect=\(aspectRatio) requested=\(animated) effective=\(effectiveAnimated) from=\(window.frame.size) to=\(adjustedFrame.size)",
            category: .player
        )

        // Apply the new frame
        window.setFrame(adjustedFrame, display: true, animate: effectiveAnimated)
    }

    /// Locks the window's resize behavior to the given aspect ratio without
    /// changing the current frame. Use this when the auto-resize setting is
    /// disabled but we still want manual resizing to be ratio-locked.
    func lockAspectRatio(_ aspectRatio: Double) {
        guard let window = activePlayerWindow else { return }
        guard aspectRatio > 0 else { return }
        if isActivePlayerWindowFullScreen {
            pendingFullScreenAspectRatio = aspectRatio
            return
        }
        if window.inLiveResize {
            pendingLiveResizeAspectLock = .lock(aspectRatio)
            return
        }
        Self.applyAspectRatioConstraint(aspectRatio, to: window)
    }

    /// Removes the window's aspect-ratio resize constraint so it resizes
    /// freely. Used by the corner layout, where the window frames the whole
    /// video-plus-panels arrangement rather than the video alone. The size
    /// floor stays enforced by `windowWillResize(_:to:)`.
    func unlockAspectRatio() {
        guard let window = activePlayerWindow else { return }
        pendingFullScreenAspectRatio = nil
        if window.inLiveResize {
            pendingLiveResizeAspectLock = .unlock
            return
        }
        // `aspectRatio` and `resizeIncrements` are mutually exclusive: setting
        // one resets the other. Assigning a zero aspect ratio does NOT clear the
        // lock — it leaves AppKit's aspect handler active with a degenerate 0:0
        // ratio, which makes interactive resize a no-op (the window can't be
        // resized at all). Resetting the increments to 1×1 is the supported way
        // to return to free resizing.
        if window === overlayParent {
            restoreOverlaySizingConstraints(on: window)
        } else {
            window.contentResizeIncrements = NSSize(width: 1, height: 1)
        }
        LoggingService.shared.debug(
            "unlockAspectRatio (corner layout) aspect=\(window.contentAspectRatio) increments=\(window.contentResizeIncrements)",
            category: .player
        )
    }

    // MARK: - Private Helpers

    private func synchronizeActiveWindowAspectRatio() {
        let appEnvironment = AppEnvironment.shared
        if appEnvironment.isCornerPanelLayoutActive {
            unlockAspectRatio()
            return
        }
        guard let aspectRatio = appEnvironment.playerService.state.videoAspectRatio,
              aspectRatio > 0 else { return }
        lockAspectRatio(aspectRatio)
        if appEnvironment.settingsManager.playerSheetAutoResize {
            resizeToFitAspectRatio(aspectRatio, animated: false)
        }
    }

    private func restoreOverlaySizingConstraints(on window: NSWindow) {
        guard let constraints = overlaySizingConstraints else { return }
        window.contentMinSize = constraints.contentMinSize
        window.minSize = constraints.minSize
        if constraints.contentAspectRatio.width > 0,
           constraints.contentAspectRatio.height > 0 {
            window.contentAspectRatio = constraints.contentAspectRatio
        } else {
            // Setting resize increments is AppKit's supported way to clear an
            // aspect constraint; assigning a zero contentAspectRatio is not.
            window.contentResizeIncrements = constraints.contentResizeIncrements
        }
    }

    private func applyPendingLiveResizeAspectLock() {
        guard let pending = pendingLiveResizeAspectLock else { return }
        pendingLiveResizeAspectLock = nil
        switch pending {
        case let .lock(ratio):
            lockAspectRatio(ratio)
        case .unlock:
            unlockAspectRatio()
        }
    }

    private func replayPendingFullScreenAspectRatio(on window: NSWindow) {
        guard let ratio = pendingFullScreenAspectRatio else { return }
        pendingFullScreenAspectRatio = nil
        guard !AppEnvironment.shared.isCornerPanelLayoutActive else { return }
        Self.applyAspectRatioConstraint(ratio, to: window)
        if AppEnvironment.shared.settingsManager.playerSheetAutoResize {
            resizeToFitAspectRatio(ratio, animated: false)
        }
    }

    /// Sets `contentAspectRatio` and a ratio-consistent minimum content size on
    /// the window so that interactive resize couples width and height
    /// proportionally and can't shrink below a usable minimum.
    static func applyAspectRatioConstraint(_ aspectRatio: Double, to window: NSWindow) {
        guard aspectRatio > 0 else { return }

        // contentAspectRatio is expressed as a ratio; using (aspectRatio, 1) keeps it exact.
        window.contentAspectRatio = NSSize(width: aspectRatio, height: 1)

        // Derive a minimum size that lies on the same ratio so the lower bound
        // doesn't force the window off-ratio (which would re-introduce bars).
        // Anchor on minHeight and scale width by aspect.
        let derivedMinWidth = max(Self.minHeight * CGFloat(aspectRatio), 320)
        let minContentSize = NSSize(width: derivedMinWidth, height: Self.minHeight)

        // Best-effort minimum. NSHostingController resets these to zero at runtime,
        // so the real resize floor is enforced in the window delegate's
        // `windowWillResize(_:to:)`; these are kept for any code path that reads
        // the window's stored minimum before the reset happens.
        window.contentMinSize = minContentSize
        window.minSize = minContentSize
    }

    private func configureWindowLevel(_ window: NSWindow, floating: Bool) {
        if floating {
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            window.level = .normal
            window.collectionBehavior = [.managed, .fullScreenPrimary]
        }
    }

    /// Initial window size for a given aspect ratio. Delegates to the shared
    /// `fittedPlayerSize` so the opening size and the later aspect-fitted size use
    /// identical math (no mismatch → no grow when the two are compared).
    private func calculateInitialWindowSize(aspectRatio: Double) -> NSSize {
        let ratio = aspectRatio > 0 ? aspectRatio : Self.defaultAspectRatio
        guard let screen = NSScreen.main else {
            return Self.fittedPlayerSize(
                for: ratio,
                screenFrame: NSRect(x: 0, y: 0, width: 1280, height: 720)
            )
        }
        return Self.fittedPlayerSize(for: ratio, screenFrame: screen.visibleFrame)
    }

    private func calculateWindowSize(for aspectRatio: Double, screenFrame: NSRect) -> NSSize {
        Self.fittedPlayerSize(for: aspectRatio, screenFrame: screenFrame)
    }

    /// Sizing math for the standalone-window path.
    /// Anchors on `targetVideoHeight`, derives width from the aspect ratio, then
    /// clamps to `maxScreenRatio` of the screen and the minimum size.
    static func fittedPlayerSize(for aspectRatio: Double, screenFrame: NSRect) -> NSSize {
        let maxWidth = screenFrame.width * maxScreenRatio
        let maxHeight = screenFrame.height * maxScreenRatio

        var width: CGFloat
        var height: CGFloat

        // Start with target video height and calculate width from aspect ratio
        height = targetVideoHeight
        width = height * aspectRatio

        // Scale down if too wide for screen
        if width > maxWidth {
            width = maxWidth
            height = width / aspectRatio
        }

        // Scale down if too tall for screen
        if height > maxHeight {
            height = maxHeight
            width = height * aspectRatio
        }

        // Apply minimum constraints
        width = max(width, minWidth)
        height = max(height, minHeight)

        return NSSize(width: width, height: height)
    }

    private func constrainToScreen(_ frame: NSRect, screen: NSScreen) -> NSRect {
        let screenFrame = screen.visibleFrame
        var adjustedFrame = frame

        // Ensure width/height don't exceed screen
        adjustedFrame.size.width = min(adjustedFrame.size.width, screenFrame.width)
        adjustedFrame.size.height = min(adjustedFrame.size.height, screenFrame.height)

        // Adjust origin to keep on screen
        if adjustedFrame.minX < screenFrame.minX {
            adjustedFrame.origin.x = screenFrame.minX
        }
        if adjustedFrame.maxX > screenFrame.maxX {
            adjustedFrame.origin.x = screenFrame.maxX - adjustedFrame.width
        }
        if adjustedFrame.minY < screenFrame.minY {
            adjustedFrame.origin.y = screenFrame.minY
        }
        if adjustedFrame.maxY > screenFrame.maxY {
            adjustedFrame.origin.y = screenFrame.maxY - adjustedFrame.height
        }

        return adjustedFrame
    }
}

/// One-shot gate shared by the fullscreen-exit notification and its timeout
/// fallback: whichever fires first runs the completion, the other is a no-op.
/// Both fire on the main thread.
private final class FullScreenExitWaiter: @unchecked Sendable {
    var observer: NSObjectProtocol?
    private var completed = false

    func finish(_ completion: @Sendable () -> Void) {
        guard !completed else { return }
        completed = true
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        completion()
    }
}

// MARK: - NSWindowDelegate

extension ExpandedPlayerWindowManager: NSWindowDelegate {
    /// Clamp interactive resize to a usable minimum size.
    ///
    /// Once `contentAspectRatio` is set, AppKit's aspect-ratio resize handler
    /// takes over and stops enforcing `minSize`/`contentMinSize` during live
    /// drags; NSHostingController also zeroes those stored minimums at runtime.
    /// So the floor is computed here from constants and applied to the proposed
    /// (already aspect-correct) frame, growing any under-sized proposal back up
    /// while preserving its ratio.
    nonisolated func windowWillResize(_ window: NSWindow, to frameSize: NSSize) -> NSSize {
        MainActor.assumeIsolated {
            // Enforce the floor from constants here rather than from
            // `window.minSize`/`contentMinSize`: NSHostingController resets those
            // to zero at runtime (even with `sizingOptions = []`), so the window's
            // stored minimum can't be trusted. AppKit already applies
            // `contentAspectRatio` to `frameSize`, so we only need to grow an
            // under-sized proposal back up to the minimum while preserving its
            // (already correct) aspect ratio.
            let isAspectLocked = window.contentAspectRatio.width > 0

            var width: CGFloat
            var height: CGFloat
            if isAspectLocked {
                let aspect = frameSize.height > 0
                    ? frameSize.width / frameSize.height
                    : CGFloat(Self.defaultAspectRatio)

                height = max(frameSize.height, Self.minHeight)
                width = height * aspect

                // Guard the width floor too (for narrow/portrait videos where the
                // height minimum alone would leave the window too thin), then rederive
                // height so the result stays on the proposed aspect ratio.
                let minWidthFloor = max(Self.minHeight * aspect, 320)
                if width < minWidthFloor {
                    width = minWidthFloor
                    height = aspect > 0 ? width / aspect : height
                }
            } else {
                // Free resize (corner layout): clamp each axis on its own.
                // Preserving the proposal's ratio here would widen the window
                // while the user drags only its bottom edge past the floor.
                width = max(frameSize.width, 320)
                height = max(frameSize.height, Self.minHeight)
            }

            return NSSize(width: width, height: height)
        }
    }

    nonisolated func windowDidEndLiveResize(_: Notification) {
        MainActor.assumeIsolated {
            applyPendingLiveResizeAspectLock()
        }
    }

    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Handle close ourselves to avoid deallocation race conditions
        MainActor.assumeIsolated {
            // Clear reference first so hide() becomes a no-op
            playerWindow = nil

            // Clear queue so closing the window fully ends the session,
            // matching the close button behavior
            appEnvironment?.queueManager.clearQueue()

            // Stop player BEFORE cleaning up window to avoid crash
            // The player must be stopped while views still exist to ensure
            // proper cleanup of render resources
            appEnvironment?.playerService.stop()

            // Update navigation state
            // Set collapsing first so mini player shows video immediately
            let navigationCoordinator = appEnvironment?.navigationCoordinator
            navigationCoordinator?.isPlayerCollapsing = true
            navigationCoordinator?.isPlayerExpanded = false

            // Clean up window, leaving native fullscreen first (orderOut on a
            // fullscreen window strands its black fullscreen space on screen)
            exitFullScreenIfNeeded(sender) {
                Task { @MainActor in
                    sender.delegate = nil
                    sender.contentViewController = nil
                    sender.orderOut(nil)

                    // Unlike hide(), this path has no animation completion to reset the
                    // flag. Left stuck true, the mini capsule mounts its video container
                    // forever and hijacks the shared render view on the next expand
                    // (player window stays black while the capsule renders the video).
                    navigationCoordinator?.isPlayerCollapsing = false
                }
            }
        }
        // Return false - we've already hidden the window with orderOut
        return false
    }

    nonisolated func windowWillEnterFullScreen(_: Notification) {
        MainActor.assumeIsolated {
            isPlayerWindowEnteringFullScreen = true
            hideCornerPanelsForFullScreen()
        }
    }

    nonisolated func windowDidEnterFullScreen(_: Notification) {
        MainActor.assumeIsolated {
            isPlayerWindowEnteringFullScreen = false
        }
    }

    nonisolated func windowDidExitFullScreen(_ notification: Notification) {
        MainActor.assumeIsolated {
            isPlayerWindowEnteringFullScreen = false
            // Mirror of the enter order: the window is back at its size
            // first, then the panels slide in. Restoring flips
            // `isCornerPanelLayoutActive` back on, so the aspect-ratio replay
            // below is skipped (the corner layout then unlocks the ratio).
            restoreCornerPanelsAfterFullScreen()
            guard let window = playerWindow else { return }
            // Restore the pinned (floating) config that toggleFullScreen
            // dropped so the window could enter primary fullscreen.
            let floating = appEnvironment?.settingsManager.macPlayerFloating ?? false
            configureWindowLevel(window, floating: floating)

            // Replay the aspect ratio that arrived while fullscreen (queue
            // advanced to a different-aspect video): restore the manual-resize
            // ratio lock, and auto-fit the window if that setting is on —
            // exactly what the aspect-change handler would have done windowed.
            replayPendingFullScreenAspectRatio(on: window)
        }
    }
}

// MARK: - Free-Resize Gate

extension AppEnvironment {
    /// Whether the player window should resize freely instead of following
    /// the video aspect ratio: the corner layout is resolved AND its panel
    /// regions are shown, so the window frames video plus panels. Hiding the
    /// panels in corner mode leaves only the video, which follows the ratio
    /// lock (and auto-fit) exactly like the stacked layout.
    var isCornerPanelLayoutActive: Bool {
        navigationCoordinator.isCornerLayoutActive && settingsManager.landscapeDetailsPanelVisible
    }
}

// MARK: - Two-Phase Window Root

/// Root view hosted in the expanded player window.
///
/// Shows a cheap black background + spinner on the first frame so the window
/// composites and fades in immediately, then defers building the heavy
/// `ExpandedPlayerSheet` by one runloop — after the window is already on screen.
/// This is the macOS equivalent of the instant loading feedback iOS shows while
/// its player window renders, and removes the perceptible "dead gap" between the
/// click and the window appearing.
private struct ExpandedPlayerWindowRoot: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var showFullPlayer = false

    var body: some View {
        ZStack {
            // Fills the window and matches the player's black background so the
            // swap to ExpandedPlayerSheet is seamless.
            Color.black

            if showFullPlayer {
                ExpandedPlayerSheet(
                    initialPortraitPanelVisible: ExpandedPlayerSheet.initialPortraitPanelVisibility(
                        settingsManager: appEnvironment?.settingsManager
                    )
                )
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            // Defer so the cheap branch composites first, then build the real
            // player while the window is already visible.
            DispatchQueue.main.async { showFullPlayer = true }
        }
    }
}

// MARK: - Main Content Window Reader

/// Invisible background view that registers ContentView's hosting window with
/// `ExpandedPlayerWindowManager`, so the inline overlay always targets the real
/// main content window (mainWindow/keyWindow point elsewhere when e.g. the
/// Settings window has focus).
struct MainContentWindowReader: NSViewRepresentable {
    func makeNSView(context _: Context) -> ReaderView {
        ReaderView()
    }

    func updateNSView(_: ReaderView, context _: Context) {}

    final class ReaderView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            Task { @MainActor in
                ExpandedPlayerWindowManager.shared.registerMainContentWindow(window)
            }
        }
    }
}

#endif
