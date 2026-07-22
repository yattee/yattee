//
//  MPVRenderViewRepresentable.swift
//  Yattee
//
//  SwiftUI representable wrapper for MPVRenderView.
//

import SwiftUI

#if os(iOS) || os(tvOS)
import UIKit

/// UIViewRepresentable wrapper for MPVRenderView on iOS/tvOS.
/// Uses a container view to properly swap the player view when backend changes.
struct MPVRenderViewRepresentable: UIViewRepresentable {
    let backend: MPVBackend

    /// Optional player state to update PiP availability
    var playerState: PlayerState?

    func makeUIView(context: Context) -> UIView {
        // Create a container that will hold the actual player view
        let container = MPVContainerView()
        container.backgroundColor = .black

        MPVLogging.log("MPVRenderViewRepresentable.makeUIView: creating container",
            details: "hasPlayerView:\(backend.playerView != nil)")

        // Add the backend's player view
        if let playerView = backend.playerView {
            container.setPlayerView(playerView)
        }

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        MPVLogging.log("MPVRenderViewRepresentable.updateUIView",
            details: "hasPlayerView:\(backend.playerView != nil)")

        // Swap the player view if backend changed
        if let container = uiView as? MPVContainerView,
           let playerView = backend.playerView {
            container.setPlayerView(playerView)
        }

        #if os(iOS)
        // Set up PiP - backend handles window availability check internally
        // and will complete setup via onDidMoveToWindow if needed
        backend.setupPiPIfNeeded(in: uiView, playerState: playerState)
        #endif
    }
}

/// Container view that properly manages player view swapping
private class MPVContainerView: UIView {
    private weak var currentPlayerView: UIView?
    private let containerID = UUID()

    // Track all living containers to enable view transfer on deinit
    private static var livingContainers = NSHashTable<MPVContainerView>.weakObjects()

    override init(frame: CGRect) {
        super.init(frame: frame)
        MPVContainerView.livingContainers.add(self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        MPVContainerView.livingContainers.add(self)
    }

    deinit {
        MPVLogging.log("MPVContainerView deinit",
            details: "id:\(containerID.uuidString.prefix(8)) hasPlayerView:\(currentPlayerView != nil)")

        // If we have the player view, transfer it to another living container
        if let playerView = currentPlayerView {
            // Find another container that's still alive and in the view hierarchy
            for container in MPVContainerView.livingContainers.allObjects {
                if container !== self && container.window != nil {
                    MPVLogging.log("MPVContainerView deinit: transferring player view to surviving container",
                        details: "from:\(containerID.uuidString.prefix(8)) to:\(container.containerID.uuidString.prefix(8))")
                    container.setPlayerView(playerView)
                    return
                }
            }
            MPVLogging.warn("MPVContainerView deinit: no surviving container to transfer player view to!")

            // Detach the shared view now instead of leaving it bound to this
            // deallocating container: otherwise SwiftUI keeps reconciling a
            // half-alive view and spins the main-thread trait update loop (100%
            // CPU hang when opening a settings detail during playback, issue #956).
            playerView.removeFromSuperview()
        }
    }

    func setPlayerView(_ playerView: UIView) {
        // Skip only if same view AND actually our subview
        // (weak ref can point to a view that's been stolen by another container)
        if playerView === currentPlayerView && playerView.superview === self {
            MPVLogging.log("MPVContainerView.setPlayerView: same view, skipping")
            return
        }

        // Check if player view is in another container
        let isInAnotherContainer = playerView.superview is MPVContainerView && playerView.superview !== self

        MPVLogging.log("MPVContainerView.setPlayerView: adding view",
            details: "container:\(containerID.uuidString.prefix(8)) wasInOtherContainer:\(isInAnotherContainer) new:\(ObjectIdentifier(playerView))")

        // Remove old view if present (different from the one we're adding)
        if let oldView = currentPlayerView, oldView !== playerView {
            MPVLogging.log("MPVContainerView: removing old view from superview")
            oldView.removeFromSuperview()
        }

        // Add new view - this automatically removes it from its current superview
        playerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        currentPlayerView = playerView
    }
}

#elseif os(macOS)
import AppKit

/// NSViewRepresentable wrapper for MPVRenderView on macOS.
/// Uses a container view to properly swap the player view when backend changes.
struct MPVRenderViewRepresentable: NSViewRepresentable {
    let backend: MPVBackend

    /// Optional player state to update PiP availability
    var playerState: PlayerState?

    func makeNSView(context: Context) -> NSView {
        // Create a container that will hold the actual player view
        let container = MPVContainerNSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        // Add the backend's player view
        if let playerView = backend.playerView {
            container.setPlayerView(playerView)
        }

        // Set up callback for when view is added to window
        // Use weak backend reference to avoid retaining during window destruction
        container.onDidMoveToWindow = { [weak container, weak backend] in
            guard let container, let backend else { return }
            backend.setupPiPIfNeeded(in: container, playerState: playerState)
        }

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Swap the player view if backend changed
        if let container = nsView as? MPVContainerNSView,
           let playerView = backend.playerView {
            container.setPlayerView(playerView)
        }

        // Try to set up PiP (will succeed when window is available)
        backend.setupPiPIfNeeded(in: nsView, playerState: playerState)
    }
}

/// Container view that properly manages player view swapping on macOS.
/// Internal (not private) so MPVBackend's render watchdog can call
/// `recoverSharedPlayerViewIfNeeded()`.
final class MPVContainerNSView: NSView {
    private weak var currentPlayerView: NSView?
    private let containerID = UUID()

    /// Short identifier used in logs.
    var shortID: String { String(containerID.uuidString.prefix(8)) }

    /// Track all living containers so a container that releases the shared
    /// player view can hand it to another container instead of orphaning it.
    private static var livingContainers = NSHashTable<MPVContainerNSView>.weakObjects()

    /// The single shared render view most recently attached to any container.
    /// Lets a container that gains a window reclaim the view when it was
    /// orphaned or left behind in a non-visible window.
    private static weak var sharedPlayerView: NSView?

    /// Callback when view is added to a window
    var onDidMoveToWindow: (() -> Void)?

    /// Whether this container lives in the player window tracked by
    /// ExpandedPlayerWindowManager. That window is the primary video surface:
    /// its containers may always claim the shared view, and nothing outside it
    /// may steal from it while it is visible.
    private var isInTrackedPlayerWindow: Bool {
        guard let window else { return false }
        return window === ExpandedPlayerWindowManager.shared.currentPlayerWindow
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        MPVContainerNSView.livingContainers.add(self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        MPVContainerNSView.livingContainers.add(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Notify when we're added to a window (not removed)
        if window != nil {
            onDidMoveToWindow?()
            reclaimSharedPlayerViewIfStranded()
        }
    }

    /// When this container gains a window, adopt the shared player view if it
    /// is currently orphaned or parented in a container whose window is gone
    /// or not visible. This is the recovery path for the expand race where the
    /// mini capsule unmounts before any windowed container exists ("no
    /// transfer target"), and for a view left behind in a stale ordered-out
    /// player window.
    private func reclaimSharedPlayerViewIfStranded() {
        guard let sharedView = Self.sharedPlayerView, sharedView.superview !== self else { return }
        let owner = sharedView.superview as? MPVContainerNSView
        // Parented outside any container (e.g. mid-transfer) — leave it alone.
        if sharedView.superview != nil, owner == nil { return }
        let ownerWindowVisible = owner?.window?.isVisible == true
        // A visible owner keeps the view — unless we are in the tracked player
        // window (the primary surface takes it even from the mini capsule
        // preview, which otherwise renders the video at thumbnail size while
        // the player window stays black). Same-window owners are left alone;
        // SwiftUI layout updates settle those.
        if let owner, ownerWindowVisible {
            guard isInTrackedPlayerWindow, owner.window !== window else { return }
        }
        LoggingService.shared.debug(
            "MPVContainerNSView[\(shortID)]: reclaiming stranded player view on window attach (previous owner: \(owner?.shortID ?? "none"), ownerWindowVisible: \(ownerWindowVisible), trackedWindow: \(isInTrackedPlayerWindow))",
            category: .mpv
        )
        setPlayerView(sharedView, bypassingStealGuard: true)
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
        // When being removed from superview, detach the player view first for a clean
        // teardown order during window destruction.
        //
        // The player view is a single SHARED instance (backend.playerView) that is
        // re-parented between containers (mini bar ⇄ expanded sheet). When presenting
        // the sheet, the new container attaches the shared view (AppKit auto-removes it
        // from the old container) BEFORE this old container is torn down. So by the time
        // we get here, `currentPlayerView` may already live in another container. Only
        // remove it if it still actually belongs to us — otherwise we would rip the
        // shared view out of its new home and blank the video (black screen on re-open,
        // and a black mini-bar preview after collapse).
        if newSuperview == nil {
            if let playerView = currentPlayerView, playerView.superview === self {
                // Hand the shared view to another living container that still has a
                // window instead of orphaning it. SwiftUI is not guaranteed to re-run
                // updateNSView on the other container (e.g. the expanded player window
                // hidden for PiP re-shown on restore), so without this transfer the
                // view can end up with no superview and the player renders only black.
                if let target = MPVContainerNSView.findTransferTarget(excluding: self) {
                    LoggingService.shared.debug(
                        "MPVContainerNSView[\(shortID)]: unmounting - transferring player view to container \(target.shortID) (windowVisible: \(target.window?.isVisible == true))",
                        category: .mpv
                    )
                    // The transfer is initiated by the current owner, so bypass
                    // the steal guard (the target may legitimately be in a
                    // not-yet-visible window, e.g. hidden for PiP).
                    target.setPlayerView(playerView, bypassingStealGuard: true)
                } else {
                    LoggingService.shared.debug(
                        "MPVContainerNSView[\(shortID)]: unmounting - no transfer target, parking player view (reclaimed when a container gains a window)",
                        category: .mpv
                    )
                    playerView.removeFromSuperview()
                    MPVContainerNSView.scheduleSharedViewAdoptionRetry()
                }
            }
            currentPlayerView = nil
            onDidMoveToWindow = nil
        }
    }

    /// Another living container that can host the shared player view.
    /// Ranking:
    /// 1. A container whose window is currently visible.
    /// 2. A container in the window still tracked by ExpandedPlayerWindowManager
    ///    (mid-presentation or hidden for PiP — it will become visible).
    /// 3. nil — park the view rather than parenting it in a stale ordered-out
    ///    window that CoreAnimation never composites (permanent black video);
    ///    `reclaimSharedPlayerViewIfStranded` re-adopts it when a container
    ///    gains a window.
    private static func findTransferTarget(excluding source: MPVContainerNSView) -> MPVContainerNSView? {
        let candidates = livingContainers.allObjects.filter { $0 !== source && $0.window != nil }
        if let visible = candidates.first(where: { $0.window?.isVisible == true }) {
            return visible
        }
        if let trackedWindow = ExpandedPlayerWindowManager.shared.currentPlayerWindow,
           let tracked = candidates.first(where: { $0.window === trackedWindow }) {
            LoggingService.shared.debug(
                "MPVContainerNSView.findTransferTarget: no visible candidate, using container \(tracked.shortID) in tracked player window",
                category: .mpv
            )
            return tracked
        }
        return nil
    }

    func setPlayerView(_ playerView: NSView, bypassingStealGuard: Bool = false) {
        // Skip only if same view AND actually our subview. The weak ref can
        // point to a view that was stolen by another container — e.g. the mini
        // player preview takes the shared render view during PiP while the
        // expanded window is hidden; on restore the view must be re-claimed
        // here or it stays orphaned and the window shows only black.
        if playerView === currentPlayerView && playerView.superview === self {
            return
        }

        if !bypassingStealGuard,
           let owner = playerView.superview as? MPVContainerNSView,
           owner !== self,
           let ownerWindow = owner.window,
           ownerWindow.isVisible,
           ownerWindow !== window {
            // Refuse to steal from a container in a visible window when this
            // container's own window is missing or not visible. The player
            // window ordered out on collapse keeps its SwiftUI hierarchy alive
            // until it deallocates, and its updateNSView would otherwise
            // re-parent the shared view into the dead window where
            // CoreAnimation never composites it (permanent black video until
            // app restart). Exemption: containers in the tracked player window
            // may claim the view before their window is visible — it is the
            // primary surface and is about to be shown.
            if window?.isVisible != true, !isInTrackedPlayerWindow {
                LoggingService.shared.debug(
                    "MPVContainerNSView[\(shortID)]: declined steal - view owned by visible container \(owner.shortID) (self window: \(window != nil), windowVisible: false, bounds: \(Int(bounds.width))x\(Int(bounds.height)))",
                    category: .mpv
                )
                return
            }
            // Conversely, never steal from the visible tracked player window:
            // the mini capsule preview (mounted alongside it in separate-window
            // mode) must not take the video out of the player window.
            if ownerWindow === ExpandedPlayerWindowManager.shared.currentPlayerWindow {
                LoggingService.shared.debug(
                    "MPVContainerNSView[\(shortID)]: declined steal - view owned by visible player window container \(owner.shortID) (self bounds: \(Int(bounds.width))x\(Int(bounds.height)))",
                    category: .mpv
                )
                return
            }
        }

        let previousSuperview = playerView.superview.map { String(describing: type(of: $0)) } ?? "nil"
        LoggingService.shared.debug(
            "MPVContainerNSView[\(shortID)].setPlayerView: attaching (reclaim: \(playerView === currentPlayerView), previousSuperview: \(previousSuperview), window: \(window != nil), windowVisible: \(window?.isVisible == true), bounds: \(Int(bounds.width))x\(Int(bounds.height)), trackedWindow: \(isInTrackedPlayerWindow))",
            category: .mpv
        )

        // Remove old view if it's a different view that still belongs to us
        if let oldView = currentPlayerView, oldView !== playerView, oldView.superview === self {
            oldView.removeFromSuperview()
        }

        // Add new view
        playerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        currentPlayerView = playerView
        MPVContainerNSView.sharedPlayerView = playerView
    }

    /// True while an adoption retry loop is running - avoids stacking loops
    /// when several triggers fire in quick succession.
    private static var adoptionRetryActive = false

    /// Watch the shared player view for ~1s and re-home it as soon as it
    /// needs it (parked with no owner, or owned by a container whose window
    /// lost visibility). This covers transitions with no container lifecycle
    /// hook to react to:
    /// - parking while the next host's window exists but is not yet visible
    ///   (sheet mid-presentation: viewDidMoveToWindow already fired and
    ///   findTransferTarget rejects non-visible windows)
    /// - sheet dismissal, where the dismissed sheet's hierarchy stays alive
    ///   holding the view inside a now-invisible window
    /// Without this the video stays black until the render watchdog (~10s).
    static func scheduleSharedViewAdoptionRetry() {
        guard !adoptionRetryActive else { return }
        adoptionRetryActive = true
        adoptionRetryTick(attempt: 0)
    }

    private static func adoptionRetryTick(attempt: Int) {
        guard attempt < 20 else {
            adoptionRetryActive = false
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard sharedPlayerView != nil else {
                adoptionRetryActive = false
                return
            }
            // quiet: while playback is tearing down there legitimately is no
            // container to adopt the view - not worth a warning per tick.
            if recoverSharedPlayerViewIfNeeded(quiet: true) {
                adoptionRetryActive = false
                (sharedPlayerView as? MPVOGLView)?.resumeRendering()
            } else {
                adoptionRetryTick(attempt: attempt + 1)
            }
        }
    }

    /// Re-attach the shared player view to a container in a visible window when
    /// it is currently orphaned or parented somewhere non-visible. Called by
    /// MPVBackend's render watchdog when video output stalls (frames consumed
    /// without a single draw). Returns true when the view was re-parented.
    @discardableResult
    static func recoverSharedPlayerViewIfNeeded(quiet: Bool = false) -> Bool {
        guard let sharedView = sharedPlayerView else { return false }
        let owner = sharedView.superview as? MPVContainerNSView
        // Parented outside any container — not ours to manage.
        if sharedView.superview != nil, owner == nil { return false }

        let trackedWindow = ExpandedPlayerWindowManager.shared.currentPlayerWindow
        let trackedWindowVisible = trackedWindow?.isVisible == true

        // Healthy when owned by a container in a visible window — unless the
        // tracked player window is on screen and the view sits outside it
        // (e.g. the mini capsule rendering the video at thumbnail size while
        // the player window shows black).
        if owner?.window?.isVisible == true,
           !trackedWindowVisible || owner?.window === trackedWindow {
            return false
        }

        // Prefer the largest container in the tracked player window (skips
        // thumbnail-sized surfaces that may share the window), then the
        // largest in any visible window.
        let candidates = livingContainers.allObjects
        func area(_ container: MPVContainerNSView) -> CGFloat {
            container.bounds.width * container.bounds.height
        }
        let target = candidates
            .filter { trackedWindowVisible && $0.window === trackedWindow }
            .max(by: { area($0) < area($1) })
            ?? candidates
            .filter { $0.window?.isVisible == true }
            .max(by: { area($0) < area($1) })
        guard let target, target !== owner else {
            if !quiet {
                LoggingService.shared.warning(
                    "MPVContainerNSView.recoverSharedPlayerViewIfNeeded: no suitable container (owner: \(owner?.shortID ?? "none"), trackedWindowVisible: \(trackedWindowVisible))",
                    category: .mpv
                )
            }
            return false
        }
        LoggingService.shared.warning(
            "MPVContainerNSView.recoverSharedPlayerViewIfNeeded: re-attaching player view from \(owner?.shortID ?? "orphaned") to container \(target.shortID) (bounds: \(Int(target.bounds.width))x\(Int(target.bounds.height)), trackedWindow: \(target.window === trackedWindow))",
            category: .mpv
        )
        target.setPlayerView(sharedView, bypassingStealGuard: true)
        return sharedView.superview === target
    }
}

#endif
