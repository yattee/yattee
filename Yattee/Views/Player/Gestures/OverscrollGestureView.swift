//
//  OverscrollGestureView.swift
//  Yattee
//
//  UIViewRepresentable that attaches an OverscrollGestureHandler to a parent UIScrollView.
//  Place this as a background on a SwiftUI ScrollView to intercept pull-down overscroll gestures.
//

#if os(iOS)
import SwiftUI
import UIKit

/// A transparent view that finds its parent UIScrollView and attaches an overscroll gesture handler.
/// Use as a `.background` on a SwiftUI `ScrollView` to intercept pull-down gestures at scroll top.
struct OverscrollGestureView: UIViewRepresentable {
    /// Whether the handler should currently be attached.
    var isEnabled: Bool = true
    /// Called during the drag with the vertical translation (positive = pulling down)
    var onDragChanged: ((CGFloat) -> Void)?
    /// Called when the drag ends with translation and predicted end translation
    var onDragEnded: ((CGFloat, CGFloat) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        // Store callbacks on coordinator
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded = onDragEnded

        guard isEnabled else {
            return view
        }

        // Schedule scroll view discovery after view is in hierarchy
        DispatchQueue.main.async {
            Self.attachIfNeeded(from: view, coordinator: context.coordinator)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update callbacks
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded = onDragEnded

        guard isEnabled else {
            context.coordinator.gestureHandler.detach()
            return
        }

        // Attach if not yet attached, or re-attach when the geometric match
        // changed (the hierarchy is flat under the SwiftUI host, so the
        // matching scroll view can differ from the one first found)
        DispatchQueue.main.async {
            Self.attachIfNeeded(from: uiView, coordinator: context.coordinator)
        }
    }

    private static func attachIfNeeded(from view: UIView, coordinator: Coordinator) {
        guard view.window != nil else { return }
        // Cheap check first: keep the current scroll view while it still
        // matches our frame (updateUIView runs on every SwiftUI update)
        if let attached = coordinator.gestureHandler.scrollView, attached.window != nil {
            let hostFrame = view.convert(view.bounds, to: nil)
            let frame = attached.convert(attached.bounds, to: nil)
            if abs(frame.minX - hostFrame.minX) < 1, abs(frame.minY - hostFrame.minY) < 1,
               abs(frame.width - hostFrame.width) < 1 {
                return
            }
        }
        guard let scrollView = findScrollView(from: view) else { return }
        if coordinator.gestureHandler.scrollView !== scrollView {
            LoggingService.shared.debug(
                "OverscrollGestureView attach",
                category: .player,
                details: "scrollView=\(Unmanaged.passUnretained(scrollView).toOpaque()) frame=\(scrollView.convert(scrollView.bounds, to: nil)) host=\(view.convert(view.bounds, to: nil))"
            )
            coordinator.gestureHandler.attach(to: scrollView)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.gestureHandler.detach()
    }

    // MARK: - Scroll View Discovery

    /// Finds the UIScrollView this view is the `.background` of.
    /// `.background` creates a separate branch, and SwiftUI hosts platform
    /// views in a mostly flat hierarchy, so a common ancestor can hold many
    /// unrelated scroll views (corner layout: side column pages + below-video
    /// panel). A background view shares its frame with the view it backs, so
    /// pick the scroll view whose window frame matches ours best.
    private static func findScrollView(from view: UIView) -> UIScrollView? {
        let hostFrame = view.convert(view.bounds, to: nil)

        // Collect all ancestors
        var ancestors: [UIView] = []
        var current: UIView? = view.superview
        while let parent = current {
            ancestors.append(parent)
            current = parent.superview
        }

        // Search from each ancestor level, starting closest
        for ancestor in ancestors {
            var scrollViews: [UIScrollView] = []
            collectScrollViews(in: ancestor, into: &scrollViews)
            guard !scrollViews.isEmpty else { continue }

            // Best geometric match: smallest frame mismatch against our own
            // frame, among scroll views that actually overlap it. Ignore tiny
            // internal scroll views.
            let candidates = scrollViews.filter { $0.frame.height > 100 }
            let scored = (candidates.isEmpty ? scrollViews : candidates).compactMap { scrollView -> (UIScrollView, CGFloat)? in
                let frame = scrollView.convert(scrollView.bounds, to: nil)
                guard hostFrame.isEmpty || frame.intersects(hostFrame) else { return nil }
                let mismatch = abs(frame.minX - hostFrame.minX) + abs(frame.minY - hostFrame.minY)
                    + abs(frame.width - hostFrame.width) + abs(frame.height - hostFrame.height)
                return (scrollView, mismatch)
            }
            if let best = scored.min(by: { $0.1 < $1.1 }) {
                return best.0
            }
            // Nothing overlaps at this level (e.g. not laid out yet) — keep
            // climbing; fall back to the old behavior at the root.
            if ancestor === ancestors.last {
                return candidates.first ?? scrollViews.first
            }
        }

        return nil
    }

    private static func collectScrollViews(in view: UIView, into result: inout [UIScrollView]) {
        for subview in view.subviews {
            if let scrollView = subview as? UIScrollView {
                result.append(scrollView)
            }
            collectScrollViews(in: subview, into: &result)
        }
    }

    // MARK: - Coordinator

    final class Coordinator {
        let gestureHandler = OverscrollGestureHandler()

        var onDragChanged: ((CGFloat) -> Void)? {
            didSet {
                gestureHandler.onDragChanged = onDragChanged
            }
        }

        var onDragEnded: ((CGFloat, CGFloat) -> Void)? {
            didSet {
                gestureHandler.onDragEnded = onDragEnded
            }
        }
    }
}
#endif
