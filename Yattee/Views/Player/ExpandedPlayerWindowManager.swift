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

    // Configuration
    private let minWidth: CGFloat = 640
    private let minHeight: CGFloat = 360
    private let maxScreenRatio: CGFloat = 0.7
    private let targetVideoHeight: CGFloat = 720
    private let defaultAspectRatio: Double = 16.0 / 9.0

    var isPresented: Bool {
        playerWindow != nil
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
            return
        }

        self.appEnvironment = appEnvironment

        // Mark expanding state for mini player coordination
        appEnvironment.navigationCoordinator.isPlayerExpanding = true

        // Get the current player mode for window configuration
        let mode = appEnvironment.settingsManager.macPlayerMode

        // Host a lightweight two-phase root instead of ExpandedPlayerSheet directly.
        // AppKit won't composite the window to screen until the hosted SwiftUI view
        // finishes its first layout pass; ExpandedPlayerSheet is heavy (MPV setup,
        // full controls, layout math), so building it inline leaves the alpha 0→1
        // fade with nothing to draw and the window only pops in after the render.
        // ExpandedPlayerWindowRoot paints black + spinner immediately, then defers
        // building ExpandedPlayerSheet by one runloop so the window appears at once.
        let playerView = ExpandedPlayerWindowRoot()
            .appEnvironment(appEnvironment)

        // Create hosting controller
        let hostingController = NSHostingController(rootView: playerView)
        // Don't let the hosting controller drive the window size from the SwiftUI
        // content's fitting size. The lightweight loading root (just a spinner) has a
        // tiny ideal size, which would otherwise shrink the window and then grow it
        // when ExpandedPlayerSheet builds. Window sizing is owned by `initialSize`
        // below and `resizeToFitAspectRatio` once the real video ratio is known.
        hostingController.sizingOptions = []

        // Calculate initial window size
        let initialSize = calculateInitialWindowSize()

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

        // Lock manual resize to the video aspect ratio. Seeded with 16:9 here;
        // updated as soon as the real video aspect ratio is known.
        applyAspectRatioConstraint(defaultAspectRatio, to: window)

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

        // Configure window level based on mode
        configureWindowLevel(window, floating: mode.isFloating)

        // Center window on screen
        window.center()

        // Store reference
        self.playerWindow = window

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
            completion?()
            return
        }

        // Mark collapsing state for mini player coordination
        appEnvironment?.navigationCoordinator.isPlayerCollapsing = true

        // Check if PiP is active - if so, just hide the window without destroying content
        // The AVSampleBufferDisplayLayer needs to stay alive while PiP is active
        let isPiPActive = (appEnvironment?.playerService.currentBackend as? MPVBackend)?.isPiPActive ?? false

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

            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    window.animator().alphaValue = 0
                }, completionHandler: hideWindow)
            } else {
                hideWindow()
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
                    completion?()
                }
            }

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

    /// Updates the window level based on floating preference.
    /// Call this when the user changes the player mode setting.
    func updateWindowLevel(floating: Bool) {
        guard let window = playerWindow else { return }
        configureWindowLevel(window, floating: floating)
    }

    /// Restores a window that was hidden for PiP mode.
    /// Call this when returning from PiP to show the player window again.
    func restoreFromPiP(animated: Bool = true) {
        guard let window = playerWindow else {
            LoggingService.shared.debug("ExpandedPlayerWindowManager: restoreFromPiP - no window to restore", category: .player)
            return
        }

        LoggingService.shared.debug("ExpandedPlayerWindowManager: restoreFromPiP called", category: .player)

        if animated {
            window.alphaValue = 0
            window.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
        } else {
            window.alphaValue = 1
            window.makeKeyAndOrderFront(nil)
        }
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
        guard let window = playerWindow else { return }
        guard aspectRatio > 0 else { return }

        // Always update the aspect-ratio lock, even if we end up not resizing here.
        applyAspectRatioConstraint(aspectRatio, to: window)

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

        // Apply the new frame
        window.setFrame(adjustedFrame, display: true, animate: animated)
    }

    /// Locks the window's resize behavior to the given aspect ratio without
    /// changing the current frame. Use this when the auto-resize setting is
    /// disabled but we still want manual resizing to be ratio-locked.
    func lockAspectRatio(_ aspectRatio: Double) {
        guard let window = playerWindow else { return }
        guard aspectRatio > 0 else { return }
        applyAspectRatioConstraint(aspectRatio, to: window)
    }

    // MARK: - Private Helpers

    /// Sets `contentAspectRatio` and a ratio-consistent `minSize` on the window
    /// so that interactive resize couples width and height proportionally.
    private func applyAspectRatioConstraint(_ aspectRatio: Double, to window: NSWindow) {
        guard aspectRatio > 0 else { return }

        // contentAspectRatio is expressed as a ratio; using (aspectRatio, 1) keeps it exact.
        window.contentAspectRatio = NSSize(width: aspectRatio, height: 1)

        // Derive a minimum size that lies on the same ratio so the lower bound
        // doesn't force the window off-ratio (which would re-introduce bars).
        // Anchor on minHeight and scale width by aspect.
        let derivedMinWidth = max(minHeight * CGFloat(aspectRatio), 320)
        window.minSize = NSSize(width: derivedMinWidth, height: minHeight)
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

    private func calculateInitialWindowSize() -> NSSize {
        guard let screen = NSScreen.main else {
            return NSSize(width: 1280, height: 720)
        }

        let screenFrame = screen.visibleFrame
        let maxWidth = screenFrame.width * maxScreenRatio
        let maxHeight = screenFrame.height * maxScreenRatio

        // Start with 16:9 aspect ratio at target height
        var width: CGFloat = targetVideoHeight * 16 / 9
        var height: CGFloat = targetVideoHeight

        // Scale down if needed
        if width > maxWidth {
            width = maxWidth
            height = width * 9 / 16
        }
        if height > maxHeight {
            height = maxHeight
            width = height * 16 / 9
        }

        return NSSize(width: max(width, minWidth), height: max(height, minHeight))
    }

    private func calculateWindowSize(for aspectRatio: Double, screenFrame: NSRect) -> NSSize {
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

// MARK: - NSWindowDelegate

extension ExpandedPlayerWindowManager: NSWindowDelegate {
    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Handle close ourselves to avoid deallocation race conditions
        MainActor.assumeIsolated {
            // Clear reference first so hide() becomes a no-op
            playerWindow = nil

            // Stop player BEFORE cleaning up window to avoid crash
            // The player must be stopped while views still exist to ensure
            // proper cleanup of render resources
            appEnvironment?.playerService.stop()

            // Clean up window
            sender.delegate = nil
            sender.contentViewController = nil
            sender.orderOut(nil)

            // Update navigation state
            // Set collapsing first so mini player shows video immediately
            appEnvironment?.navigationCoordinator.isPlayerCollapsing = true
            appEnvironment?.navigationCoordinator.isPlayerExpanded = false
        }
        // Return false - we've already hidden the window with orderOut
        return false
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
    @State private var showFullPlayer = false

    var body: some View {
        ZStack {
            // Fills the window and matches the player's black background so the
            // swap to ExpandedPlayerSheet is seamless.
            Color.black

            if showFullPlayer {
                ExpandedPlayerSheet()
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
#endif
