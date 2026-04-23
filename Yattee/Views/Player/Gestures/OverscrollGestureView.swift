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

        // Schedule scroll view discovery after view is in hierarchy
        DispatchQueue.main.async {
            if let scrollView = Self.findScrollView(from: view) {
                context.coordinator.gestureHandler.attach(to: scrollView)
            }
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update callbacks
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded = onDragEnded

        // If not attached yet, try again
        if context.coordinator.gestureHandler.scrollView == nil {
            DispatchQueue.main.async {
                if let scrollView = Self.findScrollView(from: uiView) {
                    context.coordinator.gestureHandler.attach(to: scrollView)
                }
            }
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.gestureHandler.detach()
    }

    // MARK: - Scroll View Discovery

    /// Finds the UIScrollView in the view hierarchy.
    /// Since .background creates a separate branch, we need to find a common ancestor
    /// and search all its descendants.
    private static func findScrollView(from view: UIView) -> UIScrollView? {
        // Collect all ancestors
        var ancestors: [UIView] = []
        var current: UIView? = view.superview
        while let parent = current {
            ancestors.append(parent)
            current = parent.superview
        }

        // Search from each ancestor level, starting closest
        for ancestor in ancestors {
            // Collect all scroll views at this level
            var scrollViews: [UIScrollView] = []
            collectScrollViews(in: ancestor, into: &scrollViews)

            if !scrollViews.isEmpty {
                // Return the first one that has meaningful content (not a tiny internal scroll view)
                if let meaningful = scrollViews.first(where: { $0.frame.height > 100 }) {
                    return meaningful
                }
                return scrollViews.first
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
