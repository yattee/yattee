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

/// Container view that properly manages player view swapping on macOS
private class MPVContainerNSView: NSView {
    private weak var currentPlayerView: NSView?

    /// Callback when view is added to a window
    var onDidMoveToWindow: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Notify when we're added to a window (not removed)
        if window != nil {
            onDidMoveToWindow?()
        }
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
        // When being removed from superview, detach player view first
        // This ensures proper cleanup order during window destruction
        if newSuperview == nil {
            currentPlayerView?.removeFromSuperview()
            currentPlayerView = nil
            onDidMoveToWindow = nil
        }
    }

    func setPlayerView(_ playerView: NSView) {
        // Skip if same view
        guard playerView !== currentPlayerView else { return }

        // Remove old view if present
        currentPlayerView?.removeFromSuperview()

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
    }
}

#endif
